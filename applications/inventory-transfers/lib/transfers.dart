import 'package:postgres/postgres.dart';

import 'validation.dart';

const _projection =
    'id::text, request_id::text, source, destination, sku, units, created_at';
Map<String, Object?> transferRow(ResultRow row) => {
  'id': row[0],
  'request_id': row[1],
  'source': row[2],
  'destination': row[3],
  'sku': row[4],
  'units': row[5],
  'created_at': (row[6] as DateTime).toUtc().toIso8601String(),
};

class TransferResult {
  final Map<String, Object?> transfer;
  final bool replay;
  const TransferResult(this.transfer, this.replay);
}

class Transfers {
  final Pool pool;
  const Transfers(this.pool);

  Future<TransferResult> submit(String org, TransferInput input) => pool.runTx(
    (tx) async {
      // Every operation uses this transaction session, including the conflict read.
      final inserted = await tx.execute(
        Sql.named('''INSERT INTO transfers.transfers
      (organization, request_id, source, destination, sku, units)
      VALUES (@org, @request::uuid, @source, @destination, @sku, @units)
      ON CONFLICT (organization, request_id) DO NOTHING
      RETURNING $_projection'''),
        parameters: input.parameters(org),
      );
      if (inserted.isEmpty) {
        // A fresh READ COMMITTED statement sees the row after the conflicting insert commits.
        final existing = await tx.execute(
          Sql.named('''SELECT $_projection FROM transfers.transfers
        WHERE organization = @org AND request_id = @request::uuid'''),
          parameters: {'org': org, 'request': input.requestId},
        );
        if (existing.isEmpty) throw StateError('Retained transfer missing');
        final row = transferRow(existing.single);
        if (row['source'] != input.source ||
            row['destination'] != input.destination ||
            row['sku'] != input.sku ||
            row['units'] != input.units) {
          throw const ApiError(409, 'request_conflict');
        }
        return TransferResult(row, true);
      }
      // Both directions acquire the same pre-existing pair in warehouse-key order.
      final balances = await tx.execute(
        Sql.named(
          '''SELECT warehouse, quantity
      FROM transfers.balances WHERE organization = @org AND sku = @sku
      AND warehouse IN (@source, @destination) ORDER BY warehouse FOR NO KEY UPDATE''',
        ),
        parameters: {
          'org': org,
          'sku': input.sku,
          'source': input.source,
          'destination': input.destination,
        },
      );
      if (balances.length != 2) throw const ApiError(404, 'unknown_balance');
      final quantities = {
        for (final row in balances) row[0] as String: row[1] as int,
      };
      if (quantities[input.source]! < input.units)
        throw const ApiError(409, 'insufficient_stock');
      if (quantities[input.destination]! > maxBalance - input.units) {
        throw const ApiError(409, 'destination_capacity');
      }
      await tx.execute(
        Sql.named('''UPDATE transfers.balances SET quantity = quantity - @units
      WHERE organization = @org AND sku = @sku AND warehouse = @source'''),
        parameters: {
          'org': org,
          'sku': input.sku,
          'source': input.source,
          'units': input.units,
        },
      );
      await tx.execute(
        Sql.named('''UPDATE transfers.balances SET quantity = quantity + @units
      WHERE organization = @org AND sku = @sku AND warehouse = @destination'''),
        parameters: {
          'org': org,
          'sku': input.sku,
          'destination': input.destination,
          'units': input.units,
        },
      );
      return TransferResult(transferRow(inserted.single), false);
    },
    settings: TransactionSettings(isolationLevel: IsolationLevel.readCommitted),
  );

  Future<List<Map<String, Object?>>> balances(
    String org,
    int count,
    String? after,
  ) => pool.run((session) async {
    final rows = await session.execute(
      Sql.named('''SELECT warehouse, sku, quantity FROM transfers.balances
      WHERE organization = @org AND (@afterWarehouse::text IS NULL OR
      (warehouse, sku) > (@afterWarehouse::text, @afterSku::text))
      ORDER BY warehouse, sku LIMIT @count'''),
      parameters: {
        'org': org,
        'afterWarehouse': after?.split('/')[0],
        'afterSku': after?.split('/')[1],
        'count': count,
      },
    );
    return rows
        .map((row) => {'warehouse': row[0], 'sku': row[1], 'quantity': row[2]})
        .toList();
  });

  Future<List<Map<String, Object?>>> list(
    String org,
    int count,
    String? before,
  ) => pool.run((session) async {
    final rows = await session.execute(
      Sql.named('''SELECT $_projection FROM transfers.transfers
      WHERE organization = @org AND (@before::bigint IS NULL OR id < @before::bigint)
      ORDER BY transfers.transfers.id DESC LIMIT @count'''),
      parameters: {'org': org, 'before': before, 'count': count},
    );
    return rows.map(transferRow).toList();
  });
}
