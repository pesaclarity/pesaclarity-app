import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/server_config.dart';
import '../../../core/network/pinned_http_client.dart';
import '../../auth/data/json_transport.dart';
import '../domain/crash_report.dart';

/// Sends a report to our server. It carries no account, token or id, and is
/// not linked to the counting token.
abstract interface class CrashReportSender {
  /// Whether the server took it. Never throws.
  Future<bool> send(CrashReport report);
}

/// `POST /v1/crash-reports` on our server.
class HttpCrashReportSender implements CrashReportSender {
  HttpCrashReportSender({required this.baseUrl, required this._transport});

  final Uri baseUrl;
  final JsonTransport _transport;

  @override
  Future<bool> send(CrashReport report) async {
    final url = baseUrl.replace(path: '${baseUrl.path}/v1/crash-reports');
    try {
      final response = await _transport.send(
        'POST',
        url,
        body: report.toJson(),
      );
      // 202 taken; 422 or 413 will never be taken, so it counts as done.
      return response.statusCode == 202 ||
          response.statusCode == 422 ||
          response.statusCode == 413;
    } on Object {
      return false;
    }
  }
}

/// The sender, or null when the build has no server address.
final crashReportSenderProvider = Provider<CrashReportSender?>((ref) {
  final baseUrl = ref.watch(serverBaseUrlProvider);
  if (baseUrl == null) return null;
  return HttpCrashReportSender(
    baseUrl: baseUrl,
    transport: IoJsonTransport(
      client: ref.watch(httpClientFactoryProvider).create(),
    ),
  );
});
