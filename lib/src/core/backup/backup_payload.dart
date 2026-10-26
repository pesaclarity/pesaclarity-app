import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'backup_exceptions.dart';

/// What a backup holds besides the database bytes.
final class BackupManifest {
  const BackupManifest({
    required this.createdAt,
    required this.schemaVersion,
    required this.databaseKeyHex,
    required this.databaseBytes,
  });

  factory BackupManifest._fromJson(Map<String, Object?> json) {
    try {
      return BackupManifest(
        createdAt: DateTime.parse(json['createdAt']! as String),
        schemaVersion: json['schemaVersion']! as int,
        databaseKeyHex: json['databaseKey']! as String,
        databaseBytes: json['databaseBytes']! as int,
      );
    } on Object {
      throw const BackupTamperedException(
        'The backup contents are unreadable.',
      );
    }
  }

  /// When the snapshot was taken, in UTC.
  final DateTime createdAt;

  /// The database schema version the snapshot was written with.
  final int schemaVersion;

  /// The SQLCipher key of the snapshot, 64 hex characters. Random per backup.
  final String databaseKeyHex;

  final int databaseBytes;

  Map<String, Object?> _toJson() => {
    'createdAt': createdAt.toUtc().toIso8601String(),
    'schemaVersion': schemaVersion,
    'databaseKey': databaseKeyHex,
    'databaseBytes': databaseBytes,
  };

  @override
  String toString() =>
      'BackupManifest(createdAt: $createdAt, schema: $schemaVersion, '
      'bytes: $databaseBytes)';
}

/// The plaintext inside a `.pcbackup` file, before encryption.
///
/// Layout: magic `PCPL`, format version (1 byte), manifest length
/// (uint32 big-endian), UTF-8 JSON manifest, then the database bytes.
abstract final class BackupPayload {
  static const _magic = [0x50, 0x43, 0x50, 0x4c];
  static const _version = 1;
  static const _prefixLength = 9;
  static const _maxManifestLength = 64 * 1024;

  /// Builds the payload stream from [manifest] and the [database] bytes.
  static Stream<List<int>> encode(
    BackupManifest manifest,
    Stream<List<int>> database,
  ) async* {
    final json = utf8.encode(jsonEncode(manifest._toJson()));
    final prefix = Uint8List(_prefixLength)..setAll(0, _magic);
    ByteData.sublistView(prefix)
      ..setUint8(4, _version)
      ..setUint32(5, json.length);
    yield prefix;
    yield json;
    yield* database;
  }

  /// Splits [payload] into its manifest and database bytes, writing the
  /// database to [databaseOut].
  ///
  /// Throws a [BackupException] if the layout is wrong or the byte count does
  /// not match the manifest. [databaseOut] is not closed.
  static Future<BackupManifest> decode(
    Stream<List<int>> payload,
    StreamSink<List<int>> databaseOut,
  ) async {
    final head = BytesBuilder(copy: false);
    BackupManifest? manifest;
    var manifestLength = -1;
    var written = 0;

    await for (final piece in payload) {
      if (manifest != null) {
        written += piece.length;
        databaseOut.add(piece);
        continue;
      }
      head.add(piece);
      if (manifestLength < 0 && head.length >= _prefixLength) {
        final bytes = head.toBytes();
        for (var i = 0; i < _magic.length; i++) {
          if (bytes[i] != _magic[i]) {
            throw const BackupTamperedException(
              'The backup contents are unreadable.',
            );
          }
        }
        final data = ByteData.sublistView(bytes);
        final version = data.getUint8(4);
        if (version != _version) {
          throw UnsupportedBackupVersionException(version);
        }
        manifestLength = data.getUint32(5);
        if (manifestLength > _maxManifestLength) {
          throw const BackupTamperedException(
            'The backup contents are unreadable.',
          );
        }
      }
      if (manifestLength >= 0 &&
          head.length >= _prefixLength + manifestLength) {
        final bytes = head.takeBytes();
        final end = _prefixLength + manifestLength;
        final Object? json;
        try {
          json = jsonDecode(
            utf8.decode(Uint8List.sublistView(bytes, _prefixLength, end)),
          );
        } on FormatException {
          throw const BackupTamperedException(
            'The backup contents are unreadable.',
          );
        }
        if (json is! Map<String, Object?>) {
          throw const BackupTamperedException(
            'The backup contents are unreadable.',
          );
        }
        manifest = BackupManifest._fromJson(json);
        if (bytes.length > end) {
          final rest = Uint8List.sublistView(bytes, end);
          written += rest.length;
          databaseOut.add(rest);
        }
      }
    }
    if (manifest == null) throw const BackupTruncatedException();
    if (written != manifest.databaseBytes) {
      throw const BackupTruncatedException();
    }
    return manifest;
  }
}
