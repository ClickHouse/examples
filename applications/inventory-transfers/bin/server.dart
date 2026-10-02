import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:inventory_transfers/api.dart';
import 'package:inventory_transfers/database.dart';
import 'package:inventory_transfers/transfers.dart';

Future<void> main() async {
  if (requiredEnv('PGUSER') != 'transfers_app')
    throw StateError('Runtime requires transfers_app');
  final port = int.parse(Platform.environment['PORT'] ?? '4000');
  if (port < 1024 || port > 65535) throw StateError('Invalid PORT');
  final pool = createPool();
  final api = Api(Transfers(pool), {
    'north': requiredEnv('NORTH_TOKEN'),
    'south': requiredEnv('SOUTH_TOKEN'),
  });
  // Fail startup on an invalid database/TLS configuration, rather than on the first write.
  await pool.execute('SELECT 1');
  final server = await shelf_io.serve(
    api.handler,
    InternetAddress.loopbackIPv4,
    port,
  );
  server.autoCompress = false;
  stdout.writeln('Inventory Transfers listening on loopback port $port');
  var stopping = false;
  Future<void> stop() async {
    if (stopping) return;
    stopping = true;
    await server.close(force: false);
    await pool.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => stop());
  ProcessSignal.sigterm.watch().listen((_) => stop());
}
