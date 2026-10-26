import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A response from the server: its status and decoded JSON body, if any.
class JsonResponse {
  const JsonResponse(this.statusCode, [this.body]);

  final int statusCode;
  final Object? body;

  /// FastAPI's error `detail`, when it is a plain message.
  String? get detail {
    final value = body;
    if (value is Map && value['detail'] is String) {
      return value['detail'] as String;
    }
    return null;
  }
}

/// Sends JSON requests. Throws [SocketException], [TimeoutException] or
/// [HttpException] when the server cannot be reached.
abstract interface class JsonTransport {
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
  });
}

/// [JsonTransport] over `dart:io`.
class IoJsonTransport implements JsonTransport {
  IoJsonTransport({
    HttpClient? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? (HttpClient()..connectionTimeout = timeout);

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
  }) async {
    final request = await _client.openUrl(method, url).timeout(timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (bearer != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    Object? decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
    }
    return JsonResponse(response.statusCode, decoded);
  }
}
