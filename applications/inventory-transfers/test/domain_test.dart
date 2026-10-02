import 'dart:convert';

import 'package:test/test.dart';
import 'package:inventory_transfers/validation.dart';

Map<String, Object> payload() => {
  'request_id': 'ABCDEF00-1234-4567-890A-123456789ABC',
  'source': 'depot',
  'destination': 'studio',
  'sku': 'bolts',
  'units': 10,
};
void main() {
  test('UUID normalization and exact bounded integers', () {
    final value = TransferInput.parse(payload());
    expect(value.requestId, 'abcdef00-1234-4567-890a-123456789abc');
    for (final units in [true, 1.5, 0, -1, maxUnits + 1, '10', null]) {
      expect(
        () => TransferInput.parse({...payload(), 'units': units}),
        throwsA(isA<ApiError>()),
      );
    }
    expect(
      TransferInput.parse({...payload(), 'units': maxUnits}).units,
      maxUnits,
    );
    expect(
      () => TransferInput.parse(
        jsonDecode(
          '{"request_id":"abcdef00-1234-4567-890a-123456789abc","source":"depot","destination":"studio","sku":"bolts","units":1.0}',
        ),
      ),
      throwsA(isA<ApiError>()),
    );
  });
  test(
    'strict fields, identifiers, distinct endpoints and bounded cursors',
    () {
      for (final body in [
        null,
        [],
        {...payload(), 'organization': 'south'},
        {...payload(), 'source': 'studio'},
        {...payload(), 'sku': 'bolts\u0000'},
        {...payload(), 'request_id': 'x' * 5000},
      ]) {
        expect(() => TransferInput.parse(body), throwsA(isA<ApiError>()));
      }
      expect(cursor('9223372036854775807'), '9223372036854775807');
      for (final c in ['0', '-1', '9223372036854775808', '1' * 1000]) {
        expect(() => cursor(c), throwsA(isA<ApiError>()));
      }
      expect(limit('100'), 100);
      expect(() => limit('101'), throwsA(isA<ApiError>()));
    },
  );
}
