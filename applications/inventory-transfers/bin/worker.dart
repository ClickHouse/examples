import 'dart:convert';
import 'dart:io';

import 'package:inventory_transfers/database.dart';
import 'package:inventory_transfers/transfers.dart';
import 'package:inventory_transfers/validation.dart';

// Independent acceptance worker: result is written atomically to a caller-chosen private file.
Future<void> main(List<String> arguments) async {
  final input = jsonDecode(arguments[0]) as Map<String, dynamic>;
  final pool = createPool(applicationName: arguments[2]);
  Map<String, Object?> output;
  try {
    final result = await Transfers(pool)
        .submit(input.remove('org') as String, TransferInput.parse(input));
    output = {'transfer': result.transfer, 'replay': result.replay};
  } on ApiError catch (error) {
    output = {'error': error.code};
  } catch (_) {
    output = {'error': 'database_failure'};
  }
  await pool.close();
  final temp = File('${arguments[1]}.tmp');
  await temp.writeAsString(jsonEncode(output));
  await temp.rename(arguments[1]);
}
