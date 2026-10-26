import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The server's base URL, set at build time with
/// `--dart-define=PESACLARITY_API_URL=https://api.example.org`.
const _apiUrl = String.fromEnvironment('PESACLARITY_API_URL');

/// Parses a server base URL, or returns null when it is missing or unsafe.
///
/// Only https is accepted, apart from plain http to the emulator host or
/// localhost for local development.
Uri? parseServerBaseUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
  const devHosts = {'localhost', '127.0.0.1', '10.0.2.2'};
  final secure =
      uri.scheme == 'https' ||
      (uri.scheme == 'http' && devHosts.contains(uri.host));
  if (!secure) return null;
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  );
}

/// The server this build talks to, or null when none is configured.
final serverBaseUrlProvider = Provider<Uri?>(
  (ref) => parseServerBaseUrl(_apiUrl),
);
