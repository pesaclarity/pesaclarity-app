import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'backup_location.dart';
import 'backup_settings_repository.dart';

/// Signs the user in to their own Google account with only the
/// `https://www.googleapis.com/auth/drive.file` scope, so the app sees just
/// the files it created.
///
/// Play builds only. The F-Droid build must never link Google Play services,
/// so it uses [UnavailableDriveAuth].
abstract interface class DriveAuth {
  static const scope = 'https://www.googleapis.com/auth/drive.file';

  /// Whether this build can sign in to Google at all.
  bool get isAvailable;

  /// The signed-in account's email, or null.
  Future<String?> currentAccount();

  /// Shows Google sign-in; returns the account email, or null if cancelled.
  Future<String?> signIn();

  /// An access token for [scope], or null when signed out.
  Future<String?> accessToken();

  Future<void> signOut();
}

/// For builds without Google sign-in.
///
/// TODO(drive): add a Play-only DriveAuth backed by Google sign-in once the
/// Play flavour can carry a dependency the F-Droid flavour does not.
class UnavailableDriveAuth implements DriveAuth {
  const UnavailableDriveAuth();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> currentAccount() async => null;

  @override
  Future<String?> signIn() async => null;

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<void> signOut() async {}
}

/// Backups in a "Pesa Clarity backups" folder in the user's own Drive,
/// through the Drive v3 REST API. Never touches the Pesa Clarity server.
class DriveBackupLocation implements BackupLocation {
  DriveBackupLocation(this._auth, {http.Client? client})
    : _client = client ?? http.Client();

  final DriveAuth _auth;
  final http.Client _client;

  static const folderName = 'Pesa Clarity backups';
  static const _folderType = 'application/vnd.google-apps.folder';
  static final _api = Uri.parse('https://www.googleapis.com/drive/v3/');
  static final _upload = Uri.parse(
    'https://www.googleapis.com/upload/drive/v3/files',
  );

  @override
  BackupLocationId get id => BackupLocationId.drive;

  Future<Map<String, String>> _headers() async {
    final token = await _auth.accessToken();
    if (token == null) {
      throw const BackupLocationException(
        'Sign in to Google Drive to use it for backups.',
      );
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<String?> _findFolder() async {
    const query =
        "name = '$folderName' and mimeType = '$_folderType' and trashed = false";
    final response = await _client.get(
      _api
          .resolve('files')
          .replace(
            queryParameters: {
              'q': query,
              'fields': 'files(id)',
              'spaces': 'drive',
            },
          ),
      headers: await _headers(),
    );
    _check(response);
    final files =
        (jsonDecode(response.body) as Map<String, Object?>)['files']!
            as List<Object?>;
    return files.isEmpty
        ? null
        : (files.first! as Map<String, Object?>)['id']! as String;
  }

  Future<String> _folder() async {
    final existing = await _findFolder();
    if (existing != null) return existing;
    final response = await _client.post(
      _api.resolve('files').replace(queryParameters: {'fields': 'id'}),
      headers: {...await _headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({'name': folderName, 'mimeType': _folderType}),
    );
    _check(response);
    return (jsonDecode(response.body) as Map<String, Object?>)['id']! as String;
  }

  @override
  Future<void> upload(File file, String fileName) async {
    final length = await file.length();
    final folder = await _folder();
    final start = await _client.post(
      _upload.replace(queryParameters: {'uploadType': 'resumable'}),
      headers: {
        ...await _headers(),
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '$length',
      },
      body: jsonEncode({
        'name': fileName,
        'parents': [folder],
      }),
    );
    _check(start);
    final session = start.headers['location'];
    if (session == null) {
      throw const BackupLocationException('Google Drive did not accept it.');
    }
    final put = http.StreamedRequest('PUT', Uri.parse(session))
      ..headers['Content-Type'] = 'application/octet-stream'
      ..contentLength = length;
    final sending = _client.send(put);
    await put.sink.addStream(file.openRead());
    await put.sink.close();
    _check(await http.Response.fromStream(await sending));
  }

  @override
  Future<List<BackupEntry>> list() async {
    final folder = await _findFolder();
    if (folder == null) return const [];
    final response = await _client.get(
      _api
          .resolve('files')
          .replace(
            queryParameters: {
              'q': "'$folder' in parents and trashed = false",
              'fields': 'files(id,name,size,createdTime)',
              'orderBy': 'createdTime desc',
              'spaces': 'drive',
            },
          ),
      headers: await _headers(),
    );
    _check(response);
    final files =
        (jsonDecode(response.body) as Map<String, Object?>)['files']!
            as List<Object?>;
    return [
      for (final row in files.cast<Map<String, Object?>>())
        if ((row['name'] as String? ?? '').endsWith('.pcbackup'))
          BackupEntry(
            id: row['id']! as String,
            name: row['name']! as String,
            createdAt: DateTime.parse(row['createdTime']! as String).toLocal(),
            sizeBytes: int.tryParse('${row['size']}'),
          ),
    ];
  }

  @override
  Future<void> download(BackupEntry entry, File destination) async {
    final request = http.Request(
      'GET',
      _api
          .resolve('files/${Uri.encodeComponent(entry.id)}')
          .replace(queryParameters: {'alt': 'media'}),
    )..headers.addAll(await _headers());
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      _check(await http.Response.fromStream(response));
    }
    final sink = destination.openWrite();
    try {
      await sink.addStream(response.stream);
    } finally {
      await sink.close();
    }
  }

  static void _check(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    throw BackupLocationException(switch (status) {
      401 || 403 => 'Sign in to Google Drive again.',
      404 => 'That backup is no longer in Google Drive.',
      _ => 'Google Drive could not take the request (error $status).',
    });
  }
}
