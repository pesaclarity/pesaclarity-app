import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;

import 'backup_location.dart';
import 'backup_settings_repository.dart';

/// Where the ngome vault lives, set at build time with
/// `--dart-define=PESACLARITY_VAULT_URL=https://...`.
///
/// Empty by default: the vault server is not deployed yet, so the vault
/// stays off until a build names it.
abstract final class VaultConfig {
  static const baseUrl = String.fromEnvironment('PESACLARITY_VAULT_URL');

  static Uri? get uri => baseUrl.isEmpty ? null : Uri.parse(baseUrl);
}

/// Supplies the signed-in device's access token for the vault.
abstract interface class VaultTokenSource {
  /// The bearer token, or null when nobody is signed in.
  Future<String?> accessToken();
}

/// Used until sign-in exists: nobody is ever signed in.
class SignedOutVaultTokenSource implements VaultTokenSource {
  const SignedOutVaultTokenSource();

  @override
  Future<String?> accessToken() async => null;
}

/// Client for the ngome vault (`/v1/vault/backups`).
///
/// The server stores opaque ciphertext and a SHA-256 of it; it never sees a
/// passphrase or key.
class VaultBackupLocation implements BackupLocation {
  VaultBackupLocation({
    required this.baseUrl,
    required this._tokens,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final VaultTokenSource _tokens;
  final http.Client _client;

  @override
  BackupLocationId get id => BackupLocationId.vault;

  Uri _backups([String? id]) =>
      baseUrl.resolve(id == null ? 'v1/vault/backups' : 'v1/vault/backups/$id');

  Future<Map<String, String>> _auth() async {
    final token = await _tokens.accessToken();
    if (token == null) {
      throw const BackupLocationException(
        'Sign in to use the Pesa Clarity vault.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  @override
  Future<void> upload(File file, String fileName) async {
    final request = http.StreamedRequest('POST', _backups())
      ..headers.addAll(await _auth())
      ..headers['Content-Type'] = 'application/octet-stream'
      ..headers['X-Content-SHA256'] = await _sha256Hex(file)
      ..contentLength = await file.length();
    final sending = _client.send(request);
    await request.sink.addStream(file.openRead());
    await request.sink.close();
    final response = await http.Response.fromStream(await _send(sending));
    _check(response.statusCode, response.body);
  }

  @override
  Future<List<BackupEntry>> list() async {
    final response = await _call(
      () async => _client.get(_backups(), headers: await _auth()),
    );
    _check(response.statusCode, response.body);
    final rows = jsonDecode(response.body) as List<Object?>;
    return [
      for (final row in rows.cast<Map<String, Object?>>())
        BackupEntry(
          id: row['id']! as String,
          name: 'Vault backup',
          createdAt: DateTime.parse(row['created_at']! as String).toLocal(),
          sizeBytes: row['size_bytes'] as int?,
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> download(BackupEntry entry, File destination) async {
    final request = http.Request('GET', _backups(entry.id))
      ..headers.addAll(await _auth());
    final response = await _send(_client.send(request));
    if (response.statusCode != 200) {
      _check(response.statusCode, await response.stream.bytesToString());
    }
    final sink = destination.openWrite();
    try {
      await sink.addStream(response.stream);
    } finally {
      await sink.close();
    }
    final expected = response.headers['x-content-sha256'];
    if (expected != null &&
        expected.toLowerCase() != await _sha256Hex(destination)) {
      await destination.delete();
      throw const BackupLocationException(
        'The download from the vault was damaged. Try again.',
      );
    }
  }

  static Future<String> _sha256Hex(File file) async {
    final sink = const DartSha256().newHashSink();
    await for (final piece in file.openRead()) {
      sink.add(piece);
    }
    sink.close();
    final hash = await sink.hash();
    return [for (final b in hash.bytes) b.toRadixString(16).padLeft(2, '0')]
        .join();
  }

  static Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on SocketException {
      throw const BackupLocationException(
        'Could not reach the vault. Check your connection.',
      );
    } on http.ClientException {
      throw const BackupLocationException(
        'Could not reach the vault. Check your connection.',
      );
    }
  }

  static Future<http.StreamedResponse> _send(
    Future<http.StreamedResponse> sending,
  ) => _call(() => sending);

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    throw BackupLocationException(switch (status) {
      401 || 403 => 'Sign in again to use the Pesa Clarity vault.',
      404 => 'That backup is no longer in the vault.',
      413 => 'This backup is larger than the vault accepts.',
      _ => 'The vault could not take the request (error $status).',
    });
  }
}
