import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'backup_exceptions.dart';

/// Argon2id cost parameters, stored in each file so they can be raised later
/// without breaking old backups.
final class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// Defaults for new backups, sized for a 2 GB RAM Android phone.
  ///
  /// RFC 9106's second recommended option (64 MiB, t = 3) with p = 1. The
  /// 64 MiB working set sits well inside what a low-memory phone gives a
  /// foreground app, and costs roughly 1 s on a desktop VM and a few seconds
  /// on an entry-level phone, which is acceptable for an occasional backup or
  /// restore. p = 1 because the pure-Dart Argon2 runs lanes sequentially, so
  /// more lanes would only add time on the phone without costing an attacker
  /// more. This is above OWASP's minimum (19 MiB, t = 2, p = 1).
  static const recommended = KdfParams(
    memoryKiB: 64 * 1024,
    iterations: 3,
    parallelism: 1,
  );

  /// Upper bounds accepted when reading a file, checked before deriving.
  static const maxMemoryKiB = 256 * 1024;
  static const maxIterations = 10;
  static const maxParallelism = 8;

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Throws [UnsupportedBackupParametersException] if outside the bounds.
  void validate() {
    if (parallelism < 1 || parallelism > maxParallelism) {
      throw UnsupportedBackupParametersException(
        'Argon2id parallelism $parallelism is out of range.',
      );
    }
    if (iterations < 1 || iterations > maxIterations) {
      throw UnsupportedBackupParametersException(
        'Argon2id iterations $iterations is out of range.',
      );
    }
    if (memoryKiB < 8 * parallelism || memoryKiB > maxMemoryKiB) {
      throw UnsupportedBackupParametersException(
        'Argon2id memory ${memoryKiB}KiB is out of range.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'KdfParams(m=${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}

/// The fixed-size header at the start of every `.pcbackup` file (format v1).
///
/// Layout, all integers big-endian:
///
/// | Offset | Size | Field |
/// | --- | --- | --- |
/// | 0 | 8 | magic `PCBK\r\n\x1a\n` |
/// | 8 | 2 | format version (1) |
/// | 10 | 2 | header length in bytes (201) |
/// | 12 | 1 | KDF id (1 = Argon2id) |
/// | 13 | 1 | Argon2id parallelism |
/// | 14 | 4 | Argon2id memory, KiB |
/// | 18 | 4 | Argon2id iterations |
/// | 22 | 16 | salt |
/// | 38 | 4 | payload chunk size, bytes |
/// | 42 | 7 | payload nonce prefix |
/// | 49 | 12 | passphrase wrap nonce |
/// | 61 | 48 | data key wrapped under the passphrase key (+ GCM tag) |
/// | 109 | 12 | recovery wrap nonce |
/// | 121 | 48 | data key wrapped under the recovery key (+ GCM tag) |
/// | 169 | 32 | SHA-256 of bytes 0..168 |
///
/// Bytes 0..48 are the associated data of both key wraps, and the whole
/// header is the associated data of every payload chunk, so any change to
/// it fails authentication. The unkeyed checksum only exists to report
/// accidental damage as damage rather than as a wrong passphrase.
final class BackupHeader {
  BackupHeader({
    required this.kdfParams,
    required List<int> salt,
    required this.chunkSize,
    required List<int> noncePrefix,
    required List<int> passphraseWrapNonce,
    required List<int> passphraseWrappedKey,
    required List<int> recoveryWrapNonce,
    required List<int> recoveryWrappedKey,
  }) : salt = _exact(salt, saltLength, 'salt'),
       noncePrefix = _exact(noncePrefix, noncePrefixLength, 'noncePrefix'),
       passphraseWrapNonce = _exact(
         passphraseWrapNonce,
         nonceLength,
         'passphraseWrapNonce',
       ),
       passphraseWrappedKey = _exact(
         passphraseWrappedKey,
         wrappedKeyLength,
         'passphraseWrappedKey',
       ),
       recoveryWrapNonce = _exact(
         recoveryWrapNonce,
         nonceLength,
         'recoveryWrapNonce',
       ),
       recoveryWrappedKey = _exact(
         recoveryWrappedKey,
         wrappedKeyLength,
         'recoveryWrappedKey',
       );

  /// Parses a complete v1 header.
  ///
  /// Checks run in an order that gives the most useful error: magic, then
  /// version, then length, then checksum, then parameter bounds.
  factory BackupHeader.parse(Uint8List bytes) {
    checkPreamble(bytes);
    if (bytes.length < length) throw const BackupTruncatedException();
    if (bytes.length != length) {
      throw const BackupTamperedException('Header has the wrong length.');
    }
    final checksum = const DartSha256()
        .hashSync(Uint8List.sublistView(bytes, 0, _checksumOffset))
        .bytes;
    for (var i = 0; i < _checksumLength; i++) {
      if (checksum[i] != bytes[_checksumOffset + i]) {
        throw const BackupTamperedException('Header checksum does not match.');
      }
    }
    final data = ByteData.sublistView(bytes);
    final kdfId = data.getUint8(12);
    if (kdfId != kdfArgon2id) {
      throw UnsupportedBackupParametersException('Unknown KDF id $kdfId.');
    }
    final kdf = KdfParams(
      parallelism: data.getUint8(13),
      memoryKiB: data.getUint32(14),
      iterations: data.getUint32(18),
    )..validate();
    final chunkSize = data.getUint32(38);
    _validateChunkSize(chunkSize);
    Uint8List slice(int start, int size) =>
        Uint8List.sublistView(bytes, start, start + size);
    return BackupHeader(
      kdfParams: kdf,
      salt: slice(22, saltLength),
      chunkSize: chunkSize,
      noncePrefix: slice(42, noncePrefixLength),
      passphraseWrapNonce: slice(49, nonceLength),
      passphraseWrappedKey: slice(61, wrappedKeyLength),
      recoveryWrapNonce: slice(109, nonceLength),
      recoveryWrappedKey: slice(121, wrappedKeyLength),
    );
  }

  static const magic = [0x50, 0x43, 0x42, 0x4b, 0x0d, 0x0a, 0x1a, 0x0a];
  static const version = 1;
  static const length = 201;

  /// Bytes needed to read magic, version and declared header length.
  static const preambleLength = 12;

  static const kdfArgon2id = 1;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const noncePrefixLength = 7;
  static const keyLength = 32;
  static const tagLength = 16;
  static const wrappedKeyLength = keyLength + tagLength;

  static const defaultChunkSize = 64 * 1024;
  static const maxChunkSize = 16 * 1024 * 1024;

  static const _wrapAadLength = 49;
  static const _checksumOffset = 169;
  static const _checksumLength = 32;

  final KdfParams kdfParams;
  final Uint8List salt;
  final int chunkSize;
  final Uint8List noncePrefix;
  final Uint8List passphraseWrapNonce;
  final Uint8List passphraseWrappedKey;
  final Uint8List recoveryWrapNonce;
  final Uint8List recoveryWrappedKey;

  /// Validates magic, version and declared length from the first
  /// [preambleLength] bytes (or fewer, if that is all the file has).
  static void checkPreamble(Uint8List bytes) {
    for (var i = 0; i < magic.length; i++) {
      if (i >= bytes.length) {
        // A prefix of the magic: a real backup cut short.
        throw i == 0
            ? const NotABackupFileException()
            : const BackupTruncatedException();
      }
      if (bytes[i] != magic[i]) throw const NotABackupFileException();
    }
    if (bytes.length < preambleLength) throw const BackupTruncatedException();
    final data = ByteData.sublistView(bytes);
    final found = data.getUint16(8);
    if (found != version) throw UnsupportedBackupVersionException(found);
    if (data.getUint16(10) != length) {
      throw const BackupTamperedException('Header has the wrong length.');
    }
  }

  /// The serialised header, including its checksum.
  Uint8List toBytes() {
    final bytes = Uint8List(length);
    bytes.setAll(0, wrapAad());
    var offset = _wrapAadLength;
    for (final part in [
      passphraseWrapNonce,
      passphraseWrappedKey,
      recoveryWrapNonce,
      recoveryWrappedKey,
    ]) {
      bytes.setAll(offset, part);
      offset += part.length;
    }
    assert(offset == _checksumOffset);
    final checksum = const DartSha256()
        .hashSync(Uint8List.sublistView(bytes, 0, _checksumOffset))
        .bytes;
    bytes.setAll(_checksumOffset, checksum);
    return bytes;
  }

  /// Associated data for both key wraps: every field before them.
  Uint8List wrapAad() {
    kdfParams.validate();
    _validateChunkSize(chunkSize);
    final bytes = Uint8List(_wrapAadLength);
    final data = ByteData.sublistView(bytes);
    bytes.setAll(0, magic);
    data
      ..setUint16(8, version)
      ..setUint16(10, length)
      ..setUint8(12, kdfArgon2id)
      ..setUint8(13, kdfParams.parallelism)
      ..setUint32(14, kdfParams.memoryKiB)
      ..setUint32(18, kdfParams.iterations);
    bytes.setAll(22, salt);
    data.setUint32(38, chunkSize);
    bytes.setAll(42, noncePrefix);
    return bytes;
  }

  static void _validateChunkSize(int chunkSize) {
    if (chunkSize < 1 || chunkSize > maxChunkSize) {
      throw UnsupportedBackupParametersException(
        'Chunk size $chunkSize is out of range.',
      );
    }
  }

  static Uint8List _exact(List<int> value, int size, String name) {
    if (value.length != size) {
      throw ArgumentError.value(value.length, name, 'must be $size bytes');
    }
    return Uint8List.fromList(value);
  }
}
