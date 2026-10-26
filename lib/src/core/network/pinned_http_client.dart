import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'certificate_pins.dart';
import 'spki.dart';

/// A TLS connection was refused because the server's key did not match the
/// pins, or pinning is misconfigured. Extends [HandshakeException] so callers
/// that already treat handshake failures as "network unavailable" need no
/// change.
class CertificatePinningException extends HandshakeException {
  const CertificatePinningException(super.message);
}

/// Checks a server's leaf certificate against [pins] for [host].
///
/// Throws [CertificatePinningException] unless the certificate's SPKI hash is
/// one of the host's pins. Fails closed: a host without pins, an invalid pin
/// set or an unreadable certificate are all refusals.
void verifyPeerCertificate(
  CertificatePins pins,
  String host,
  Uint8List? certificateDer,
) {
  final error = pins.error;
  if (error != null) throw CertificatePinningException(error);
  final expected = pins.forHost(host);
  if (expected == null) {
    throw CertificatePinningException('$host is not a pinned host');
  }
  if (certificateDer == null) {
    throw CertificatePinningException('$host sent no certificate');
  }
  final String actual;
  try {
    actual = spkiSha256(certificateDer);
  } on FormatException {
    throw CertificatePinningException('$host sent an unreadable certificate');
  }
  if (!expected.contains(actual)) {
    throw CertificatePinningException('$host key does not match its pins');
  }
}

/// Makes the [HttpClient] every network client in the app must use.
///
/// When pins are configured, connections go only to pinned hosts over https,
/// and the server's key is checked right after the TLS handshake, before any
/// request bytes (such as a bearer token) are written. When no pins are
/// configured, the client relies on the platform's certificate checks alone.
class HttpClientFactory {
  HttpClientFactory(
    this.pins, {
    this.context,
    this.connectionTimeout = const Duration(seconds: 20),
  });

  final CertificatePins pins;

  /// Trusted roots; null uses the platform's. Tests pass their own.
  final SecurityContext? context;

  final Duration connectionTimeout;

  /// Whether clients from [create] enforce pins.
  bool get pinning => pins.isConfigured;

  HttpClient create() {
    final client = HttpClient(context: context)
      ..connectionTimeout = connectionTimeout;
    if (!pinning) return client;
    return client
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
    if (!url.isScheme('https')) {
      throw CertificatePinningException('${url.host} must use https');
    }
    // Reject before connecting when the host can never pass.
    final error = pins.error;
    if (error != null) throw CertificatePinningException(error);
    if (pins.forHost(url.host) == null) {
      throw CertificatePinningException('${url.host} is not a pinned host');
    }

    final task = await SecureSocket.startConnect(
      url.host,
      url.port,
      context: context,
    );
    final verified = task.socket.then((socket) {
      try {
        verifyPeerCertificate(pins, url.host, socket.peerCertificate?.der);
      } catch (_) {
        socket.destroy();
        rethrow;
      }
      return socket;
    });
    return ConnectionTask.fromSocket<Socket>(verified, task.cancel);
  }
}

/// Pins from the build config (`PESACLARITY_CERT_PINS`).
final certificatePinsProvider = Provider<CertificatePins>(
  (ref) => CertificatePins.fromEnvironment(),
);

/// The single source of [HttpClient]s for auth, backup and federated
/// learning calls.
final httpClientFactoryProvider = Provider<HttpClientFactory>(
  (ref) => HttpClientFactory(ref.watch(certificatePinsProvider)),
);
