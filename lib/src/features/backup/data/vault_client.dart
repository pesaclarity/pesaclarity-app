import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;

import '../../../core/integrity/integrity_attestor.dart';
import '../../../core/network/connection_errors.dart';
import '../../../domain/spaces/space.dart';
import '../../auth/domain/auth_models.dart';
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

/// Nobody is ever signed in, such as in builds without a server.
class SignedOutVaultTokenSource implements VaultTokenSource {
  const SignedOutVaultTokenSource();

  @override
  Future<String?> accessToken() async => null;
}

/// The signed-in account's access token, from [read].
class SessionVaultTokenSource implements VaultTokenSource {
  const SessionVaultTokenSource(this._read);

  final Future<String?> Function() _read;

  @override
  Future<String?> accessToken() => _read();
}

/// Client for the ngome vault (`/v1/vault/backups`).
///
/// The server stores opaque ciphertext and a SHA-256 of it; it never sees a
/// passphrase or key.
class VaultBackupLocation implements BackupLocation {
  VaultBackupLocation({
    required this.baseUrl,
    required this._tokens,
    required this._client,
    this._integrity,
  });

  final Uri baseUrl;
  final VaultTokenSource _tokens;
  final http.Client _client;

  /// Adds a Play Integrity token or App Attest assertion to uploads when
  /// the build can make one.
  final IntegrityHeaderHook? _integrity;

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
  Future<void> upload(File file, String fileName) => _guard(() async {
    final digest = await _sha256(file);
    final request = http.StreamedRequest('POST', _backups())
      ..headers.addAll(await _auth())
      ..headers.addAll(await _integrity?.headersForDigest(digest) ?? const {})
      ..headers['Content-Type'] = 'application/octet-stream'
      ..headers['X-Content-SHA256'] = _hex(digest)
      ..headers['X-Backup-Space'] = backupSpaceFromName(fileName)
      ..contentLength = await file.length();
    final sending = _client.send(request);
    final writing = () async {
      await request.sink.addStream(file.openRead());
      await request.sink.close();
    }();
    // Offline, sending fails before anything reads the body, and writing
    // it would then wait for ever: the answer decides, and the write only
    // matters once the request went through.
    writing.ignore();
    final sent = await sending;
    await writing;
    final response = await http.Response.fromStream(sent);
    _check(response.statusCode, response.body);
  });

  @override
  Future<List<BackupEntry>> list() => _guard(() async {
    final response = await _client.get(_backups(), headers: await _auth());
    _check(response.statusCode, response.body);
    final rows = jsonDecode(response.body) as List<Object?>;
    return [
      for (final row in rows.cast<Map<String, Object?>>())
        BackupEntry(
          id: row['id']! as String,
          name: 'Vault backup',
          createdAt: DateTime.parse(row['created_at']! as String).toLocal(),
          sizeBytes: row['size_bytes'] as int?,
          space: row['space'] as String? ?? personalSpaceId,
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });

  @override
  Future<void> delete(BackupEntry entry) => _guard(() async {
    final response = await _client.delete(
      _backups(entry.id),
      headers: await _auth(),
    );
    if (response.statusCode == 404) return;
    _check(response.statusCode, response.body);
  });

  @override
  Future<void> download(BackupEntry entry, File destination) =>
      _guard(() async {
        final request = http.Request('GET', _backups(entry.id))
          ..headers.addAll(await _auth());
        final response = await _client.send(request);
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
            expected.toLowerCase() != _hex(await _sha256(destination))) {
          await destination.delete();
          throw const BackupLocationException(
            'The download from the vault was damaged. Try again.',
          );
        }
      });

  /// Runs [work], turning everything that can go wrong on the way to the
  /// vault into a [BackupLocationException]: no connection (including
  /// renewing the sign-in offline), the session ending, or the server
  /// failing. Only the backup's own file errors pass through.
  static Future<T> _guard<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on BackupLocationException {
      rethrow;
    } on AuthFailure catch (failure) {
      throw switch (failure.kind) {
        AuthFailureKind.network => _offline,
        AuthFailureKind.sessionEnded => const BackupLocationException(
          'Sign in again to use the Pesa Clarity vault.',
        ),
        _ => const BackupLocationException(
          'The vault is busy right now. Try again in a minute.',
        ),
      };
    } on FileSystemException {
      rethrow;
    } on Object catch (error) {
      if (isConnectionError(error)) throw _offline;
      rethrow;
    }
  }

  static const _offline = BackupLocationException.offline(
    'Could not reach the vault. Check your connection.',
  );

  static Future<List<int>> _sha256(File file) async {
    final sink = const DartSha256().newHashSink();
    await for (final piece in file.openRead()) {
      sink.add(piece);
    }
    sink.close();
    return (await sink.hash()).bytes;
  }

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  static void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    throw BackupLocationException(switch (status) {
      401 => 'Sign in again to use the Pesa Clarity vault.',
      // The server could not verify the app or phone (Play Integrity).
      403 =>
        'The vault takes backups from the Google Play version of Pesa '
            'Clarity. Your phone or SD card works for this backup.',
      503 => 'The vault is busy right now. Try again in a minute.',
      404 => 'That backup is no longer in the vault.',
      413 => 'This backup is larger than the vault accepts.',
      _ => 'The vault could not take the request (error $status).',
    });
  }
}
