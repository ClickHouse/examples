import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:inventory_transfers/api.dart';
import 'package:inventory_transfers/transfers.dart';

void main() {
  test(
    'real HTTP health, authentication before body and strict JSON boundaries',
    () async {
      // Lazy pool: these preflight routes reject before any database operation.
      final pool = Pool.withEndpoints([
        Endpoint(host: '127.0.0.1', database: 'unused'),
      ]);
      final token = 'n' * 32;
      final api = Api(Transfers(pool), {'north': token, 'south': 's' * 32});
      final server = await shelf_io.serve(
        api.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      final client = HttpClient();
      try {
        Future<int> call(String path, {String? body, bool auth = true}) async {
          final request = await client.openUrl(
            body == null ? 'GET' : 'POST',
            Uri.parse('http://127.0.0.1:${server.port}$path'),
          );
          if (auth) request.headers.set('authorization', 'Bearer $token');
          if (body != null) {
            request.headers.contentType = ContentType.json;
            request.write(body);
          }
          final response = await request.close();
          await response.drain<void>();
          return response.statusCode;
        }

        expect(await call('/health', auth: false), 200);
        expect(await call('/transfers', auth: false, body: 'x' * 5000), 401);
        expect(await call('/transfers', body: 'x' * 5000), 413);
        expect(await call('/transfers', body: '{bad'), 400);
        expect(
          await call('/transfers', body: jsonEncode({'units': true})),
          400,
        );
        expect(await call('/balances?limit=101'), 400);
      } finally {
        client.close(force: true);
        await server.close(force: true);
        await pool.close();
      }
    },
  );
}
