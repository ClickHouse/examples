import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'transfers.dart';
import 'validation.dart';

Response jsonResponse(int status, Object body) => Response(
  status,
  body: jsonEncode(body),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    // An early body rejection must not reuse a connection with unread request bytes.
    if (status >= 400) 'connection': 'close',
  },
);

bool equalToken(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

class Api {
  final Transfers store;
  final Map<String, String> tokens;
  var _active = 0;
  Api(this.store, this.tokens) {
    if (tokens.length != 2 ||
        tokens.values.toSet().length != 2 ||
        tokens.values.any(
          (token) => !RegExp(r'^[!-~]{32,128}$').hasMatch(token),
        )) {
      throw StateError(
        'Configure two distinct 32–128 character organization tokens',
      );
    }
  }

  Handler get handler {
    final router = Router();
    router.get('/health', (_) => jsonResponse(200, {'status': 'up'}));
    router.get('/balances', (Request request) async {
      final query = request.url.queryParameters;
      if (query.keys.any((k) => !{'limit', 'after'}.contains(k)))
        throw const ApiError(400, 'invalid_query');
      final after = query['after'];
      if (after != null) {
        final parts = after.split('/');
        if (parts.length != 2) throw const ApiError(400, 'invalid_cursor');
        key(parts[0]);
        key(parts[1]);
      }
      final rows = await store.balances(
        request.context['org'] as String,
        limit(query['limit']),
        after,
      );
      return jsonResponse(200, {
        'rows': rows,
        'next_after': rows.isEmpty
            ? null
            : '${rows.last['warehouse']}/${rows.last['sku']}',
      });
    });
    router.get('/transfers', (Request request) async {
      final query = request.url.queryParameters;
      if (query.keys.any((k) => !{'limit', 'before'}.contains(k)))
        throw const ApiError(400, 'invalid_query');
      final rows = await store.list(
        request.context['org'] as String,
        limit(query['limit']),
        cursor(query['before']),
      );
      return jsonResponse(200, {
        'rows': rows,
        'next_before': rows.isEmpty ? null : rows.last['id'],
      });
    });
    router.post('/transfers', (Request request) async {
      final input = TransferInput.parse(await readJson(request));
      final result = await store.submit(
        request.context['org'] as String,
        input,
      );
      return jsonResponse(result.replay ? 200 : 201, {
        'transfer': result.transfer,
        'replay': result.replay,
      });
    });
    return (request) async {
      if (request.url.path == 'health' && request.method == 'GET')
        return router.call(request);
      final authorization = request.headers['authorization'] ?? '';
      String? org;
      for (final entry in tokens.entries) {
        if (equalToken(authorization, 'Bearer ${entry.value}')) org = entry.key;
      }
      // Authentication and admission precede reading the body or scheduling database work.
      if (org == null) return jsonResponse(401, {'error': 'unauthorized'});
      if (_active >= 8) return jsonResponse(503, {'error': 'busy'});
      _active++;
      try {
        return await router.call(request.change(context: {'org': org}));
      } on ApiError catch (error) {
        return jsonResponse(error.status, {'error': error.code});
      } on ServerException catch (error) {
        if (error.code == '23503')
          return jsonResponse(404, {'error': 'unknown_balance'});
        if (error.code == '55P03' || error.code == '57014')
          return jsonResponse(503, {'error': 'retry_request_id'});
        return jsonResponse(500, {'error': 'database_failure'});
      } catch (_) {
        // A lost commit response has an unknown outcome: retry the same retained request ID.
        return jsonResponse(503, {'error': 'retry_request_id'});
      } finally {
        _active--;
      }
    };
  }
}

Future<Object?> readJson(Request request) async {
  if ((request.headers['content-type'] ?? '').split(';').first !=
      'application/json') {
    throw const ApiError(415, 'json_required');
  }
  final length = int.tryParse(request.headers['content-length'] ?? '');
  if (length != null && length > 4096)
    throw const ApiError(413, 'body_too_large');
  final bytes = <int>[];
  try {
    await for (final chunk in request.read().timeout(
      const Duration(seconds: 3),
    )) {
      if (bytes.length + chunk.length > 4096)
        throw const ApiError(413, 'body_too_large');
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const ApiError(400, 'invalid_json');
  } on TimeoutException {
    throw const ApiError(408, 'body_timeout');
  }
}
