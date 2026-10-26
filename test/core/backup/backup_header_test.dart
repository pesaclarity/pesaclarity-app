import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

List<int> _range(int start, int end) => [for (var i = start; i < end; i++) i];

void main() {
  // Built by hand from the documented layout; checksum computed with Python.
  final knownHeader = _hex(
    '5043424b0d0a1a0a000100c90101000100000000000300010203040506070809'
    '0a0b0c0d0e0f00010000a0a1a2a3a4a5a6b0b1b2b3b4b5b6b7b8b9babbc0c1c2'
    'c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2'
    'e3e4e5e6e7e8e9eaebecedeeef101112131415161718191a1b20212223242526'
    '2728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40414243444546'
    '4748494a4b4c4d4e4fb997f9ee4a6a8eb9eb10105d69f26297d4f2bfdfd3e952'
    '63baed131cef76cff4',
  );

  group('known-answer header', () {
    test('parses every field', () {
      final header = BackupHeader.parse(knownHeader);
      expect(header.kdfParams, KdfParams.recommended);
      expect(header.salt, _range(0, 16));
      expect(header.chunkSize, 65536);
      expect(header.noncePrefix, _range(0xa0, 0xa7));
      expect(header.passphraseWrapNonce, _range(0xb0, 0xbc));
      expect(header.passphraseWrappedKey, _range(0xc0, 0xf0));
      expect(header.recoveryWrapNonce, _range(0x10, 0x1c));
      expect(header.recoveryWrappedKey, _range(0x20, 0x50));
    });

    test('serialises back to the same bytes', () {
      expect(BackupHeader.parse(knownHeader).toBytes(), knownHeader);
    });
  });

  group('rejects', () {
    test('a file without the magic', () {
      final bytes = Uint8List.fromList(knownHeader)..[0] = 0x51;
      expect(
        () => BackupHeader.parse(bytes),
        throwsA(isA<NotABackupFileException>()),
      );
      expect(
        () => BackupHeader.parse(Uint8List(0)),
        throwsA(isA<NotABackupFileException>()),
      );
    });

    test('another format version, before checking anything else', () {
      final bytes = Uint8List.fromList(knownHeader)..[9] = 2;
      expect(
        () => BackupHeader.parse(bytes),
        throwsA(
          isA<UnsupportedBackupVersionException>().having(
            (e) => e.version,
            'version',
            2,
          ),
        ),
      );
    });

    test('a truncated header', () {
      for (final length in [4, 11, 100, 200]) {
        expect(
          () =>
              BackupHeader.parse(Uint8List.sublistView(knownHeader, 0, length)),
          throwsA(isA<BackupTruncatedException>()),
          reason: 'length $length',
        );
      }
    });

    test('any changed byte after the version', () {
      for (var i = 12; i < knownHeader.length; i++) {
        final bytes = Uint8List.fromList(knownHeader)..[i] ^= 0x01;
        expect(
          () => BackupHeader.parse(bytes),
          throwsA(isA<BackupTamperedException>()),
          reason: 'byte $i',
        );
      }
    });

    test('KDF parameters that would exhaust a phone', () {
      final header = BackupHeader.parse(knownHeader);
      final greedy = BackupHeader(
        kdfParams: const KdfParams(
          memoryKiB: 4 * 1024 * 1024,
          iterations: 3,
          parallelism: 1,
        ),
        salt: header.salt,
        chunkSize: header.chunkSize,
        noncePrefix: header.noncePrefix,
        passphraseWrapNonce: header.passphraseWrapNonce,
        passphraseWrappedKey: header.passphraseWrappedKey,
        recoveryWrapNonce: header.recoveryWrapNonce,
        recoveryWrappedKey: header.recoveryWrappedKey,
      );
      expect(
        greedy.toBytes,
        throwsA(isA<UnsupportedBackupParametersException>()),
      );
      // Same check on read, with a valid checksum, via a hand-edited header.
      final bytes = Uint8List.fromList(knownHeader);
      ByteData.sublistView(bytes).setUint32(14, 4 * 1024 * 1024);
      expect(
        () => BackupHeader.parse(_withChecksum(bytes)),
        throwsA(isA<UnsupportedBackupParametersException>()),
      );
    });
  });
}

/// Recomputes the trailing checksum, as a careless or hostile editor would.
Uint8List _withChecksum(Uint8List bytes) {
  final digest = const DartSha256().hashSync(bytes.sublist(0, 169)).bytes;
  return Uint8List.fromList(bytes)..setAll(169, digest);
}
