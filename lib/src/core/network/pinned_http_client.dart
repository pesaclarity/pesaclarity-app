import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trusted_roots.dart';

/// A connection was refused because the host is not one of ours, the
/// request was not https, or pinning is misconfigured. Extends
/// [HandshakeException] so callers that already treat handshake failures as
/// "network unavailable" need no change. A chain that does not end in a
/// trusted root fails the TLS handshake itself.
class CertificatePinningException extends HandshakeException {
  const CertificatePinningException(super.message);
}

/// Makes the [HttpClient] every network client in the app must use.
///
/// When pinning is configured, connections go only to pinned hosts over
/// https, and the TLS handshake trusts only the configured roots, so a
/// server whose chain ends elsewhere is refused before any request bytes
/// (such as a bearer token) are written. When it is not configured, the
/// client relies on the platform's certificate checks alone.
class HttpClientFactory {
  HttpClientFactory(
    this.roots, {
    this.context,
    this.connectionTimeout = const Duration(seconds: 20),
  });

  final TrustedRoots roots;

  /// Trusted roots when pinning is off; null uses the platform's. Tests pass
  /// their own.
  final SecurityContext? context;

  final Duration connectionTimeout;

  /// Whether clients from [create] enforce pinning.
  bool get pinning => roots.isConfigured;

  late final SecurityContext? _pinnedContext = roots.error == null
      ? roots.securityContext()
      : null;

  /// A client for third-party services whose authorities we do not choose,
  /// such as Google Drive. Never use it for our own servers.
  HttpClient createUnpinned() =>
      HttpClient(context: context)..connectionTimeout = connectionTimeout;

  HttpClient create() {
    if (!pinning) return createUnpinned();
    return HttpClient(context: _pinnedContext)
      ..connectionTimeout = connectionTimeout
      // The pinned socket is opened here, so a proxy would bypass the check.
      ..findProxy = ((_) => 'DIRECT')
      ..badCertificateCallback = ((_, _, _) => false)
      ..connectionFactory = _connectPinned;
  }

  Future<ConnectionTask<Socket>> _connectPinned(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    final error = roots.error;
    if (error != null) throw CertificatePinningException(error);
    if (!url.isScheme('https')) {
      throw CertificatePinningException('${url.host} must use https');
    }
    if (!roots.isPinned(url.host)) {
      throw CertificatePinningException('${url.host} is not a pinned host');
    }
    return SecureSocket.startConnect(
      url.host,
      url.port,
      context: _pinnedContext,
    );
  }
}

/// Pinning from the build config (`PESACLARITY_PINNED_HOSTS` and
/// `PESACLARITY_TRUSTED_ROOTS`).
final trustedRootsProvider = Provider<TrustedRoots>(
  (ref) => TrustedRoots.fromEnvironment(),
);

/// The single source of [HttpClient]s for auth, backup and federated
/// learning calls.
final httpClientFactoryProvider = Provider<HttpClientFactory>(
  (ref) => HttpClientFactory(ref.watch(trustedRootsProvider)),
);
