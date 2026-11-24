import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  final Map<String, dynamic>? details;
  ApiException(this.status, this.message, [this.details]);

  @override
  String toString() => message;
}

/// Unique key for retry-safe POSTs (Idempotency-Key header).
String newIdempotencyKey() {
  final r = Random.secure();
  return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 30)}-${r.nextInt(1 << 30)}';
}

class ApiClient {
  String baseUrl;
  String? accessToken;
  String? refreshToken;
  void Function(String? access, String? refresh)? onTokensChanged;
  void Function()? onSessionExpired;

  Future<bool>? _refreshing;

  ApiClient({required this.baseUrl});

  Future<bool> _refresh() {
    _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
    return _refreshing!;
  }

  Future<bool> _doRefresh() async {
    final rt = refreshToken;
    if (rt == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'refresh_token': rt}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return false;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      accessToken = data['access_token'] as String?;
      refreshToken = data['refresh_token'] as String?;
      onTokensChanged?.call(accessToken, refreshToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    bool retry = true,
  }) async {
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final h = <String, String>{'accept': 'application/json'};
    if (body != null) h['content-type'] = 'application/json';
    if (accessToken != null) h['authorization'] = 'Bearer $accessToken';
    if (headers != null) h.addAll(headers);

    http.Response res;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      final timeout = const Duration(seconds: 20);
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: h, body: encoded).timeout(timeout);
          break;
        case 'PATCH':
          res = await http.patch(uri, headers: h, body: encoded).timeout(timeout);
          break;
        case 'PUT':
          res = await http.put(uri, headers: h, body: encoded).timeout(timeout);
          break;
        default:
          res = await http.get(uri, headers: h).timeout(timeout);
      }
    } on Exception {
      throw ApiException(0, 'Cannot reach the server. Check your connection and the server address.');
    }

    final isAuthPath = path == '/auth/login' || path == '/auth/refresh';
    if (res.statusCode == 401 && retry && !isAuthPath && refreshToken != null) {
      if (await _refresh()) {
        return request(method, path, query: query, body: body, headers: headers, retry: false);
      }
      accessToken = null;
      refreshToken = null;
      onTokensChanged?.call(null, null);
      onSessionExpired?.call();
    }

    dynamic data;
    if (res.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        data = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;

    var message = 'Request failed (${res.statusCode})';
    Map<String, dynamic>? details;
    if (data is Map<String, dynamic>) {
      if (data['message'] is String) message = data['message'] as String;
      if (data['details'] is Map<String, dynamic>) details = data['details'] as Map<String, dynamic>;
    }
    throw ApiException(res.statusCode, message, details);
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) => request('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) =>
      request('POST', path, body: body ?? <String, dynamic>{}, headers: headers);
}
