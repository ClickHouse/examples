import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:inventory_transfers/database.dart';

int sequence = 0;
String requestId() =>
    '10000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}';
Map<String, Object> payload({
  String? id,
  String source = 'depot',
  String destination = 'studio',
  int units = 10,
}) => {
  'request_id': id ?? requestId(),
  'source': source,
  'destination': destination,
  'sku': 'bolts',
  'units': units,
};

Future<Connection> privileged(String user, String password) => Connection.open(
  endpoint(user: user, password: password),
  settings: ConnectionSettings(
    sslMode: SslMode.verifyFull,
    securityContext: trust(requiredEnv('PGSSLROOTCERT')),
    connectTimeout: const Duration(seconds: 5),
    queryTimeout: const Duration(seconds: 20),
    applicationName: 'transfers-acceptance-control',
  ),
);

void main() {
  group(
    'Cloud acceptance',
    () {
      late Connection owner, admin;
      late Pool pool;
      late Process server;
      late String executable;
      final client = HttpClient();
      final logs = <String>[];
      Future<(int, Map<String, dynamic>)> call(
        String path, {
        Map<String, Object?>? body,
        String? raw,
        bool auth = true,
        bool south = false,
      }) async {
        final request = await client.openUrl(
          body != null || raw != null ? 'POST' : 'GET',
          Uri.parse('http://127.0.0.1:4000$path'),
        );
        if (auth)
          request.headers.set(
            'authorization',
            'Bearer ${requiredEnv(south ? 'SOUTH_TOKEN' : 'NORTH_TOKEN')}',
          );
        if (body != null || raw != null) {
          request.headers.contentType = ContentType.json;
          final bytes = utf8.encode(raw ?? jsonEncode(body));
          request.contentLength = bytes.length;
          request.add(bytes);
        }
        print(
          'HTTP ${request.method} $path bodyBytes=${request.contentLength} auth=$auth',
        );
        final response = await request.close();
        return (
          response.statusCode,
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>,
        );
      }

      Future<void> start() async {
        // Whitelist the runtime environment; no administrator or migration credentials.
        final environment = {
          for (final name in [
            'PGHOST',
            'PGPORT',
            'PGDATABASE',
            'PGUSER',
            'PGPASSWORD',
            'PGSSLROOTCERT',
            'NORTH_TOKEN',
            'SOUTH_TOKEN',
          ])
            name: requiredEnv(name),
          'PORT': '4000',
        };
        server = await Process.start(
          executable,
          [],
          environment: environment,
          includeParentEnvironment: false,
        );
        server.stdout.transform(utf8.decoder).listen(logs.add);
        server.stderr.transform(utf8.decoder).listen(logs.add);
        for (var attempt = 0; attempt < 100; attempt++) {
          try {
            final response = await call('/health', auth: false);
            if (response.$1 == 200) return;
          } catch (_) {}
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('Server did not become ready');
      }

      Future<List<int>> quantities() async => (await owner.execute(
        "SELECT quantity FROM transfers.balances WHERE organization='north' AND sku='bolts' AND warehouse IN ('depot','studio') ORDER BY warehouse",
      )).map((row) => row[0] as int).toList();
      Future<void> sql(String statement) async {
        await owner.execute(statement);
      }

      Future<bool> hasTransfer(String id) async => (await owner.execute(
        Sql.named(
          "SELECT 1 FROM transfers.transfers WHERE organization='north' AND request_id=@id::uuid",
        ),
        parameters: {'id': id},
      )).isNotEmpty;
      Future<void> denied(String statement, String code) async {
        await expectLater(
          pool.execute(statement),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'SQLSTATE', code),
          ),
        );
      }

      Future<Process> worker(
        Map<String, Object> body,
        String name,
        String output,
      ) => Process.start(requiredEnv('WORKER_EXECUTABLE'), [
        jsonEncode({...body, 'org': 'north'}),
        output,
        name,
      ]);
      Future<Map<String, dynamic>> finish(Process process, String path) async {
        expect(await process.exitCode.timeout(const Duration(seconds: 15)), 0);
        return jsonDecode(await File(path).readAsString())
            as Map<String, dynamic>;
      }

      Future<void> blocked(List<String> names) async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await admin.execute('SELECT pg_stat_clear_snapshot()');
          final rows = await admin.execute(
            Sql.named(
              '''SELECT application_name FROM pg_stat_activity
          WHERE application_name=ANY(@names::text[]) AND cardinality(pg_blocking_pids(pid))>0''',
            ),
            parameters: {'names': names},
          );
          if (rows.length == names.length) return;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        fail('Independent workers were not observed blocked');
      }

      setUpAll(() async {
        executable = requiredEnv('SERVER_EXECUTABLE');
        owner = await privileged(
          'transfers_migration',
          requiredEnv('MIGRATION_PASSWORD'),
        );
        admin = await privileged(
          requiredEnv('ADMIN_USER'),
          requiredEnv('ADMIN_PASSWORD'),
        );
        pool = createPool(applicationName: 'transfers-acceptance');
        print(
          'Actual PostgreSQL: ${(await owner.execute('SHOW server_version')).single.single}',
        );
        await start();
      });
      setUp(() async {
        await sql("UPDATE transfers.balances SET quantity=1000");
      });
      tearDownAll(() async {
        server.kill(ProcessSignal.sigterm);
        expect(await server.exitCode.timeout(const Duration(seconds: 15)), 0);
        print('Server output: ${logs.join()}');
        client.close(force: true);
        await pool.close();
        await owner.close();
        await admin.close();
      });

      test('HTTP organization scope, retained replay, malformed input and tuple pagination', () async {
        final body = payload();
        final created = await call('/transfers', body: body);
        expect(created.$1, 201);
        expect(created.$2['replay'], false);
        final repeated = await call(
          '/transfers',
          body: {
            ...body,
            'request_id': (body['request_id'] as String).toUpperCase(),
          },
        );
        expect(repeated.$1, 200);
        expect(repeated.$2['transfer'], created.$2['transfer']);
        expect(
          (await call('/transfers', body: {...body, 'units': 11})).$1,
          409,
        );
        expect((await call('/transfers', body: body, south: true)).$1, 201);
        expect(
          (await call(
            '/transfers',
            body: {...body, 'organization': 'south'},
          )).$1,
          400,
        );
        expect(
          (await call(
            '/transfers',
            body: {...payload(), 'source': 'foreign-only'},
          )).$1,
          404,
        );
        for (final value in [true, 1.5, 0, 1000001, '10']) {
          expect(
            (await call('/transfers', body: {...payload(), 'units': value})).$1,
            400,
          );
        }
        expect((await call('/transfers', raw: 'x' * 5000)).$1, 413);
        expect(
          (await call('/transfers', raw: 'x' * 5000, auth: false)).$1,
          401,
        );
        expect((await call('/transfers', raw: '{bad')).$1, 400);
        expect(
          (await call(
            '/transfers',
            body: {...payload(), 'sku': 'bolts\u0000'},
          )).$1,
          400,
        );
        await sql(
          "INSERT INTO transfers.warehouses VALUES ('north','a','A'),('north','a-branch','Branch'),('south','foreign-only','Foreign')",
        );
        await sql(
          "INSERT INTO transfers.balances SELECT w.organization,w.id,s.id,1000 FROM transfers.warehouses w JOIN transfers.skus s USING(organization) WHERE w.id IN ('a','a-branch','foreign-only')",
        );
        final expected = (await owner.execute(
          "SELECT warehouse || '/' || sku FROM transfers.balances WHERE organization='north' ORDER BY warehouse,sku",
        )).map((r) => r[0]).toList();
        final seen = <String>[];
        String? after;
        for (var page = 0; page < 30; page++) {
          final result = await call(
            '/balances?limit=1${after == null ? '' : '&after=${Uri.encodeQueryComponent(after)}'}',
          );
          expect(result.$1, 200);
          final rows = result.$2['rows'] as List;
          if (rows.isEmpty) break;
          final row = rows.single as Map;
          seen.add('${row['warehouse']}/${row['sku']}');
          after = result.$2['next_after'] as String;
        }
        expect(seen, expected);
        expect(seen.toSet().length, seen.length);
        expect((await call('/balances?limit=101')).$1, 400);
        expect((await call('/transfers?before=9223372036854775808')).$1, 400);
        final north = (await call('/transfers')).$2['rows'] as List;
        final south =
            (await call('/transfers', south: true)).$2['rows'] as List;
        expect(north.length, 1);
        expect(south.length, 1);
        expect(north.single['id'], isNot(south.single['id']));
        // Now the foreign warehouse really exists, but only in the other organization.
        expect(
          (await call(
            '/transfers',
            body: {...payload(), 'source': 'foreign-only'},
          )).$1,
          404,
        );
      });

      test('native constraints and restricted runtime grants', () async {
        await denied("UPDATE transfers.transfers SET units=1", '42501');
        await denied("DELETE FROM transfers.transfers", '42501');
        await denied("UPDATE transfers.balances SET warehouse='x'", '42501');
        await denied("CREATE TABLE transfers.forbidden (id int)", '42501');
        await denied("CREATE SCHEMA forbidden", '42501');
        await denied("CREATE TEMP TABLE forbidden (id int)", '42501');
        await denied("SELECT * FROM transfers.schema_versions", '42501');
        await denied("UPDATE transfers.balances SET quantity=-1", '23514');
        await denied(
          "INSERT INTO transfers.transfers (organization,request_id,source,destination,sku,units) VALUES ('north','20000000-0000-4000-8000-000000000001','depot','foreign-only','bolts',1)",
          '23503',
        );
        await denied(
          "INSERT INTO transfers.transfers (organization,request_id,source,destination,sku,units) VALUES ('north','20000000-0000-4000-8000-000000000002','depot','depot','bolts',1)",
          '23514',
        );
        expect(await quantities(), [1000, 1000]);
      });

      test(
        'failure after debit rolls back both balances and retained transfer',
        () async {
          final body = payload();
          final before = await quantities();
          await sql(
            r'''CREATE FUNCTION transfers.reject_credit() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
        IF NEW.organization='north' AND NEW.warehouse='studio' AND NEW.sku='bolts' AND NEW.quantity>OLD.quantity THEN
          RAISE EXCEPTION 'acceptance credit failure'; END IF; RETURN NEW; END $$''',
          );
          await sql(
            'CREATE TRIGGER acceptance_credit BEFORE UPDATE ON transfers.balances FOR EACH ROW EXECUTE FUNCTION transfers.reject_credit()',
          );
          try {
            expect((await call('/transfers', body: body)).$1, 500);
            expect(await quantities(), before);
            expect(await hasTransfer(body['request_id'] as String), false);
          } finally {
            await sql('DROP TRIGGER acceptance_credit ON transfers.balances');
            await sql('DROP FUNCTION transfers.reject_credit()');
          }
          expect((await call('/transfers', body: body)).$1, 201);
          expect(await quantities(), [990, 1010]);
        },
      );

      test(
        'independent same-key workers block and return one retained record',
        () async {
          final body = payload();
          final directory = await Directory.systemTemp.createTemp(
            'transfers-same-',
          );
          await admin.execute('BEGIN');
          await admin.execute(
            "SELECT 1 FROM transfers.balances WHERE organization='north' AND sku='bolts' AND warehouse IN ('depot','studio') ORDER BY warehouse FOR NO KEY UPDATE",
          );
          final first = await worker(
            body,
            'transfers-same-a',
            '${directory.path}/a.json',
          );
          final second = await worker(
            body,
            'transfers-same-b',
            '${directory.path}/b.json',
          );
          try {
            await blocked(['transfers-same-a', 'transfers-same-b']);
          } finally {
            await admin.execute('COMMIT');
          }
          final a = await finish(first, '${directory.path}/a.json');
          final b = await finish(second, '${directory.path}/b.json');
          expect(a['transfer'], b['transfer']);
          expect([a['replay'], b['replay']], containsAll([true, false]));
          expect(await quantities(), [990, 1010]);
          await directory.delete(recursive: true);
        },
      );

      test('independent opposite-direction contention and actual HTTP concurrency conserve sum', () async {
        final directory = await Directory.systemTemp.createTemp(
          'transfers-opposite-',
        );
        await admin.execute('BEGIN');
        await admin.execute(
          "SELECT 1 FROM transfers.balances WHERE organization='north' AND sku='bolts' AND warehouse IN ('depot','studio') ORDER BY warehouse FOR NO KEY UPDATE",
        );
        final a = await worker(
          payload(units: 17),
          'transfers-opposite-a',
          '${directory.path}/a.json',
        );
        final b = await worker(
          payload(source: 'studio', destination: 'depot', units: 23),
          'transfers-opposite-b',
          '${directory.path}/b.json',
        );
        try {
          await blocked(['transfers-opposite-a', 'transfers-opposite-b']);
        } finally {
          await admin.execute('COMMIT');
        }
        expect((await finish(a, '${directory.path}/a.json'))['error'], isNull);
        expect((await finish(b, '${directory.path}/b.json'))['error'], isNull);
        expect(await quantities(), [1006, 994]);
        final results = await Future.wait([
          call('/transfers', body: payload(units: 11)),
          call(
            '/transfers',
            body: payload(source: 'studio', destination: 'depot', units: 7),
          ),
        ]);
        expect(results.map((r) => r.$1), [201, 201]);
        expect(await quantities(), [1002, 998]);
        expect((await quantities()).reduce((a, b) => a + b), 2000);
        await directory.delete(recursive: true);
      });

      test('competing withdrawals cannot overspend and destination overflow leaves no record', () async {
        await sql(
          "UPDATE transfers.balances SET quantity=10 WHERE organization='north' AND sku='bolts' AND warehouse='depot'",
        );
        final results = await Future.wait([
          call('/transfers', body: payload(units: 7)),
          call('/transfers', body: payload(units: 7)),
        ]);
        expect(results.map((r) => r.$1).toList()..sort(), [201, 409]);
        expect(await quantities(), [3, 1007]);
        await sql(
          "UPDATE transfers.balances SET quantity=1000000000 WHERE organization='north' AND sku='bolts' AND warehouse='studio'",
        );
        final body = payload(units: 1);
        expect(
          (await call('/transfers', body: body)).$2['error'],
          'destination_capacity',
        );
        expect(await quantities(), [3, 1000000000]);
        expect(await hasTransfer(body['request_id'] as String), false);
      });

      test('real driver certificate and hostname failures with positive same-endpoint control', () async {
        Future<List<int>> reject(Endpoint target, String ca) async {
          try {
            final connection = await Connection.open(
              target,
              settings: ConnectionSettings(
                sslMode: SslMode.verifyFull,
                securityContext: trust(ca),
                connectTimeout: const Duration(seconds: 5),
              ),
            );
            await connection.close();
          } on BadCertificateException catch (error) {
            // The pinned driver reports verification through this specific exception.
            return error.certificate.sha1;
          }
          fail('Invalid TLS unexpectedly succeeded');
        }

        final wrongCaCertificate = await reject(
          endpoint(),
          requiredEnv('WRONG_CA'),
        );
        final address = (await InternetAddress.lookup(requiredEnv('PGHOST')))
            .firstWhere((a) => a.type == InternetAddressType.IPv4)
            .address;
        final wrongNameCertificate = await reject(
          endpoint(host: address),
          requiredEnv('PGSSLROOTCERT'),
        );
        expect(wrongNameCertificate, wrongCaCertificate);
        final connection = await Connection.open(
          endpoint(),
          settings: ConnectionSettings(
            sslMode: SslMode.verifyFull,
            securityContext: trust(requiredEnv('PGSSLROOTCERT')),
          ),
        );
        expect((await connection.execute('SELECT 1')).single.single, 1);
        await connection.close();
      });

      test('original compiled process exits before replacement and persisted request replays', () async {
        final body = payload(units: 31);
        final original = await call('/transfers', body: body);
        expect(original.$1, 201);
        final before = await quantities();
        final oldPid = server.pid;
        server.kill(ProcessSignal.sigterm);
        expect(await server.exitCode.timeout(const Duration(seconds: 15)), 0);
        await start();
        expect(server.pid, isNot(oldPid));
        final replay = await call('/transfers', body: body);
        expect(replay.$1, 200);
        expect(replay.$2['transfer'], original.$2['transfer']);
        expect(await quantities(), before);
        expect((await call('/balances')).$1, 200);
      });
    },
    skip: Platform.environment['RUN_CLOUD'] != 'true',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
