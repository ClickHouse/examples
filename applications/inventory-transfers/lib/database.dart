import 'dart:io';

import 'package:postgres/postgres.dart';

String requiredEnv(String name, [Map<String, String>? env]) {
  final value = (env ?? Platform.environment)[name];
  if (value == null || value.isEmpty) throw StateError('Missing $name');
  return value;
}

Endpoint endpoint({String? host, String? user, String? password}) => Endpoint(
  host: host ?? requiredEnv('PGHOST'),
  port: int.parse(Platform.environment['PGPORT'] ?? '5432'),
  database: requiredEnv('PGDATABASE'),
  username: user ?? requiredEnv('PGUSER'),
  password: password ?? requiredEnv('PGPASSWORD'),
);

SecurityContext trust(String path) =>
    SecurityContext(withTrustedRoots: false)..setTrustedCertificates(path);

Pool createPool({String applicationName = 'inventory-transfers'}) =>
    Pool.withEndpoints(
      [endpoint()],
      settings: PoolSettings(
        maxConnectionCount: 4,
        maxConnectionAge: const Duration(minutes: 10),
        connectTimeout: const Duration(seconds: 5),
        queryTimeout: const Duration(seconds: 8),
        sslMode: SslMode.verifyFull,
        securityContext: trust(requiredEnv('PGSSLROOTCERT')),
        applicationName: applicationName,
        timeZone: 'UTC',
        onOpen: (connection) async {
          await connection.execute("SET statement_timeout = '5s'");
          await connection.execute("SET lock_timeout = '3s'");
          await connection.execute(
            "SET idle_in_transaction_session_timeout = '10s'",
          );
        },
      ),
    );
