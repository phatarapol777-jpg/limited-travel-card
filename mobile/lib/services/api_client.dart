import 'dart:convert';
import 'package:http/http.dart' as http;

const String _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:4000/api');

/// Resolves the configured API base URL against the current page origin when it's
/// a relative path (e.g. '/api'), since package:http requires absolute URLs on web.
String get apiBaseUrl {
  if (_configuredApiBaseUrl.startsWith('http')) return _configuredApiBaseUrl;
  return Uri.base.resolve(_configuredApiBaseUrl).toString();
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  String? token;

  Map<String, String> _headers({bool json = true}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Uri _u(String path) => Uri.parse('$apiBaseUrl$path');

  dynamic _decode(http.Response res) {
    Map<String, dynamic>? body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body;
    }
    throw ApiException(body?['error']?.toString() ?? 'Request failed (${res.statusCode})');
  }

  Future<dynamic> get(String path) async {
    final res = await http.get(_u(path), headers: _headers());
    return _decode(res);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final res = await http.post(_u(path), headers: _headers(), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<dynamic> put(String path, [Map<String, dynamic>? body]) async {
    final res = await http.put(_u(path), headers: _headers(), body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await http.delete(_u(path), headers: _headers());
    return _decode(res);
  }
}

final apiClient = ApiClient();
