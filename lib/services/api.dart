import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class Api {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
  String? token;
  void Function()? onUnauthorized;
  final http.Client client;
  Api({http.Client? client}) : client = client ?? http.Client();
  Future<dynamic> request(String method, String path, [Object? body]) async {
    final requestToken = token;
    final req = http.Request(method, Uri.parse('$baseUrl/api$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final http.Response response;
    final timeout =
        (path.startsWith('/documents/') &&
                (path.endsWith('/extract') || path.endsWith('/classify'))) ||
            path.startsWith('/assistant/threads/') ||
            path == '/report-chat'
        ? const Duration(minutes: 6)
        : const Duration(seconds: 60);
    try {
      response = await http.Response.fromStream(
        await client.send(req).timeout(timeout),
      ).timeout(timeout);
    } catch (_) {
      throw ApiError(
        0,
        'Could not reach Med.ai. Check your internet connection and try again.',
      );
    }
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      throw ApiError(
        response.statusCode,
        'The server returned an unexpected response.',
      );
    }
    if (response.statusCode == 401 &&
        !path.startsWith('/auth/') &&
        requestToken == token) {
      onUnauthorized?.call();
    }
    if (response.statusCode >= 400) {
      final detail = data is Map ? data['detail'] : null;
      throw ApiError(
        response.statusCode,
        detail is String
            ? detail
            : detail is List && detail.isNotEmpty
            ? 'Check ${detail.first['loc']?.last ?? 'input'}: ${detail.first['msg'] ?? 'invalid value'}'
            : response.statusCode == 409
            ? 'Record changed on another device. Resolve the sync conflict.'
            : 'Request rejected (${response.statusCode}). Check your entered data.',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> upload(
    String id,
    List<int> bytes,
    String kind,
    String language,
  ) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/documents'),
    );
    req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll({'client_id': id, 'kind': kind, 'language': language});
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: 'document.jpg'),
    );
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 70)),
      ).timeout(const Duration(seconds: 70));
    } catch (_) {
      throw ApiError(
        0,
        'The image could not be uploaded. Check Tailscale and your connection, then retry. Your queued photo is kept.',
      );
    }
    if (response.statusCode >= 400) {
      final reason = switch (response.statusCode) {
        401 => 'Sign in again before uploading this prescription.',
        413 => 'This image is too large. Choose a smaller prescription photo.',
        415 => 'The image format is unsupported. Select a JPG or PNG photo.',
        409 =>
          'This upload conflicts with an existing document. Select the prescription photo again.',
        _ =>
          'Document upload failed (${response.statusCode}). Your queued photo is kept; retry when connected.',
      };
      throw ApiError(response.statusCode, reason);
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<int>> image(String id) async {
    final r = await client
        .get(
          Uri.parse('$baseUrl/api/documents/$id'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200)
      throw ApiError(r.statusCode, 'Could not load document');
    return r.bodyBytes;
  }

  void close() => client.close();
}
