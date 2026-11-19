import '../../auth/data/json_transport.dart';

/// The header that carries the monthly counting token (ADR 0024).
const countTokenHeader = 'Count-Token';

/// Where the signed app status comes from.
abstract interface class AppStatusSource {
  /// The signed response for this build, or null when the server could not
  /// be reached or did not answer with one. Never throws. [countToken] is
  /// this month's counting token, when counting is on.
  Future<Object?> fetch({
    required String version,
    required String build,
    required String platform,
    String? countToken,
  });
}

/// `GET /v1/app-status` on our server. It sends only the version, build and
/// platform, and while counting is on the month's random counting token in
/// the `Count-Token` header (never in the URL, which request logs record).
/// No account, sign-in token, device or install id.
class HttpAppStatusSource implements AppStatusSource {
  HttpAppStatusSource({required this.baseUrl, required this._transport});

  final Uri baseUrl;
  final JsonTransport _transport;

  @override
  Future<Object?> fetch({
    required String version,
    required String build,
    required String platform,
    String? countToken,
  }) async {
    final url = baseUrl.replace(
      path: '${baseUrl.path}/v1/app-status',
      queryParameters: {
        'version': version,
        'build': build,
        'platform': platform,
      },
    );
    try {
      final response = await _transport.send(
        'GET',
        url,
        headers: {countTokenHeader: ?countToken},
      );
      return response.statusCode == 200 ? response.body : null;
    } on Object {
      // Offline, refused or malformed: no notices, and never a block.
      return null;
    }
  }
}
