import 'dart:convert';
import 'dart:io';

import 'package:fpt_server_shared/fpt_server_shared.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Thrown for any non-2xx response, carrying the REST API's own stable
/// `error.code` — see `docs/rest-api.md#errors` in the fpt_server repo.
class FptRequestError implements Exception {
  FptRequestError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// A GET response paired with its headers — only `getJobLog` needs the
/// headers (`X-Log-Next-Offset` drives polling), everything else just wants
/// the decoded body.
class HttpResult {
  const HttpResult(this.body, this.headers);

  final String body;
  final Map<String, String> headers;
}

/// Client for the fpt_server REST API (`docs/rest-api.md`).
///
/// Unlike a Discord-facing surface there is no login step — auth is a
/// static API key sent as `X-API-Key` on every request. GET responses are
/// cached only for the `/actions` catalogue (rarely changes); job/status
/// endpoints are always fetched fresh since callers rely on them for
/// near-real-time state.
///
/// It is also the [ActionTransport] the typed `FptActions` calls run over, so
/// a tool never spells an action name or a parameter key itself.
class FptClient implements ActionTransport {
  factory FptClient({http.Client? client, String? baseUrl, String? apiKey}) {
    final resolvedBaseUrl =
        baseUrl ?? Platform.environment['FPT_SERVER_BASE_URL'] ?? '';
    return FptClient._(
      client: client ?? _trustingClient(resolvedBaseUrl),
      baseUrl: resolvedBaseUrl,
      apiKey: apiKey ?? Platform.environment['FPT_SERVER_API_KEY'] ?? '',
    );
  }

  FptClient._({
    required http.Client client,
    required this.baseUrl,
    required String apiKey,
  })  : _client = client,
        _apiKey = apiKey;

  final http.Client _client;
  final String baseUrl;
  final String _apiKey;

  /// fpt_server serves a self-signed certificate over LAN (no public CA can
  /// issue one for a `.local` hostname). Trusting it blanket-wide would
  /// silently accept a cert from anywhere; scoping the callback to the exact
  /// configured host keeps the bypass limited to the one server this client
  /// is built to talk to.
  static http.Client _trustingClient(String baseUrl) {
    final expectedHost = Uri.tryParse(baseUrl)?.host;
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => host == expectedHost;
    return IOClient(inner);
  }

  final Map<String, _CacheEntry> _cache = {};

  /// Only endpoints in this set are cached; everything else always hits the
  /// network.
  static const _cacheableTtl = {'/actions': Duration(minutes: 5)};

  void clearCache() => _cache.clear();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_apiKey.isNotEmpty) 'X-API-Key': _apiKey,
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// Performs a GET request, caching the response only for paths configured
  /// in [_cacheableTtl] (matched by prefix, ignoring the query string).
  Future<Map<String, dynamic>> getJson(String path) async {
    final result = await _getRaw(path);
    return jsonDecode(result.body) as Map<String, dynamic>;
  }

  Future<HttpResult> _getRaw(String path) async {
    final cacheKey = path.split('?').first;
    final ttl = _cacheableTtl[cacheKey];

    if (ttl != null) {
      final cached = _cache[path];
      if (cached != null && DateTime.now().isBefore(cached.expiresAt)) {
        return cached.result;
      }
    }

    final response = await _client.get(_uri(path), headers: _headers);
    _throwIfError(response);
    final result = HttpResult(response.body, response.headers);
    if (ttl != null) {
      _cache[path] = _CacheEntry(result, DateTime.now().add(ttl));
    }
    return result;
  }

  /// GET that also returns response headers, uncached. Used for
  /// `/jobs/{id}/log`, whose `X-Log-Next-Offset` header drives polling.
  Future<HttpResult> getWithHeaders(String path) => _getRaw(path);

  /// POST helper. Clears the cache since a mutation may invalidate cached
  /// catalogues.
  Future<Map<String, dynamic>> postJson(
    String path, [
    Map<String, Object?> body = const {},
  ]) async {
    clearCache();
    final response = await _client.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    _throwIfError(response);
    if (response.body.isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> invokeAction(
    String name,
    Map<String, Object?> params,
  ) =>
      postJson('/actions/${Uri.encodeComponent(name)}', params);

  void _throwIfError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var code = 'request_failed';
    var message = 'Request failed with status code ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map) {
        code = (error['code'] as String?) ?? code;
        message = (error['message'] as String?) ?? message;
      }
    } catch (_) {
      // Body wasn't JSON (or wasn't the expected shape) — fall back to the
      // generic status-based message rather than failing to report the
      // original error at all.
    }
    throw FptRequestError(response.statusCode, code, message);
  }

  void close() => _client.close();
}

class _CacheEntry {
  const _CacheEntry(this.result, this.expiresAt);

  final HttpResult result;
  final DateTime expiresAt;
}
