class ApiError implements Exception {
  final int status;
  final String code;
  const ApiError(this.status, this.code);
}

const maxBalance = 1000000000;
const maxUnits = 1000000;
final _key = RegExp(r'^[a-z][a-z0-9-]{0,31}$');
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String key(Object? value) {
  if (value is! String || !_key.hasMatch(value)) {
    throw const ApiError(400, 'invalid_identifier');
  }
  return value;
}

String uuid(Object? value) {
  if (value is! String || value.length != 36 || !_uuid.hasMatch(value)) {
    throw const ApiError(400, 'invalid_request_id');
  }
  return value.toLowerCase();
}

class TransferInput {
  final String requestId, source, destination, sku;
  final int units;
  const TransferInput(
    this.requestId,
    this.source,
    this.destination,
    this.sku,
    this.units,
  );

  factory TransferInput.parse(Object? body) {
    const fields = {'request_id', 'source', 'destination', 'sku', 'units'};
    if (body is! Map<String, dynamic> ||
        body.length != fields.length ||
        body.keys.any((field) => !fields.contains(field))) {
      throw const ApiError(400, 'invalid_fields');
    }
    final units = body['units'];
    if (units is! int || units < 1 || units > maxUnits) {
      throw const ApiError(400, 'invalid_units');
    }
    final source = key(body['source']);
    final destination = key(body['destination']);
    if (source == destination) throw const ApiError(400, 'same_warehouse');
    return TransferInput(
      uuid(body['request_id']),
      source,
      destination,
      key(body['sku']),
      units,
    );
  }

  Map<String, Object> parameters(String organization) => {
    'org': organization,
    'request': requestId,
    'source': source,
    'destination': destination,
    'sku': sku,
    'units': units,
  };
}

int limit(String? value) {
  if (value == null) return 25;
  if (!RegExp(r'^[0-9]{1,3}$').hasMatch(value))
    throw const ApiError(400, 'invalid_limit');
  final n = int.parse(value);
  if (n < 1 || n > 100) throw const ApiError(400, 'invalid_limit');
  return n;
}

String? cursor(String? value) {
  if (value == null) return null;
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    throw const ApiError(400, 'invalid_cursor');
  }
  return value;
}
