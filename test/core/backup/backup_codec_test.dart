import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';

// Cheap Argon2id settings keep the suite fast; one test uses the defaults.
const _fastKdf = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const _chunk = 1000;
const _passphrase = 'mvua ya jioni 2026';
const _headerLength = 201;
const _tag = 16;

Uint8List _payload(int length, [int seed = 1]) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// Splits [bytes] into uneven pieces, as a file or network stream would.
Stream<List<int>> _pieces(List<int> bytes, [int size = 333]) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, min(i + size, bytes.length));
  }
}

Future<Uint8List> _collect(Stream<List<int>> stream) async {
  final out = BytesBuilder(copy: false);
  await for (final piece in stream) {
    out.add(piece);
  }
  return out.takeBytes();
}

Future<Uint8List> _encrypt(
  List<int> payload, {
  RecoveryKey? recoveryKey,
  KdfParams kdf = _fastKdf,
  int chunkSize = _chunk,
  Random? random,
}) {
  final codec = BackupCodec(
    kdfParams: kdf,
    chunkSize: chunkSize,
    random: random,
  );
  return _collect(
    codec.encrypt(
      _pieces(payload),
      passphrase: _passphrase,
      recoveryKey: recoveryKey ?? RecoveryKey.generate(),
    ),
  );
}

Future<Uint8List> _decrypt(
  Uint8List file, [
  BackupCredential credential = const PassphraseCredential(_passphrase),
]) async {
  final unlocked = await BackupCodec().unlock(_pieces(file), credential);
  await unlocked.verify(_pieces(file));
  return _collect(unlocked.decrypt(_pieces(file, 4096)));
}

Uint8List _withChecksum(Uint8List file) {
  final digest = const DartSha256().hashSync(file.sublist(0, 169)).bytes;
  return Uint8List.fromList(file)..setAll(169, digest);
}

void main() {
  group('round trip', () {
    for (final length in [
      0,
      1,
      _chunk - 1,
      _chunk,
      _chunk + 1,
      3 * _chunk,
      10007,
    ]) {
      test('$length bytes with the passphrase', () async {
        final payload = _payload(length);
        final file = await _encrypt(payload);
        final fullChunks = length ~/ _chunk;
        final chunkCount = length % _chunk == 0 && length > 0
            ? fullChunks
            : fullChunks + 1;
        expect(file.length, _headerLength + length + chunkCount * _tag);
        expect(await _decrypt(file), payload);
      });
    }

    test('with the recovery key, including its typed-in form', () async {
      final recoveryKey = RecoveryKey.generate();
      final payload = _payload(4321);
      final file = await _encrypt(payload, recoveryKey: recoveryKey);
      final typed = RecoveryKey.parse(
        recoveryKey.toDisplayString().toLowerCase(),
      );
      expect(await _decrypt(file, RecoveryKeyCredential(typed)), payload);
    });

    test('with the recommended Argon2id parameters', () async {
      final payload = _payload(5000);
      final file = await _encrypt(payload, kdf: KdfParams.recommended);
      expect(
        BackupHeader.parse(file.sublist(0, _headerLength)).kdfParams,
        KdfParams.recommended,
      );
      expect(await _decrypt(file), payload);
    });

    test('a whole payload in one piece and the default chunk size', () async {
      final payload = _payload(200000);
      final codec = BackupCodec(kdfParams: _fastKdf);
      final file = await _collect(
        codec.encrypt(
          Stream.value(payload),
          passphrase: _passphrase,
          recoveryKey: RecoveryKey.generate(),
        ),
      );
      expect(await _decrypt(file), payload);
    });

    test('never repeats keys or nonces between backups', () async {
      final payload = _payload(100);
      final a = await _encrypt(payload);
      final b = await _encrypt(payload);
      expect(a.sublist(22, 169), isNot(b.sublist(22, 169)));
      expect(a.sublist(_headerLength), isNot(b.sublist(_headerLength)));
    });

    test('is deterministic given the same random source', () async {
      final key = RecoveryKey.fromBytes(List.filled(32, 9));
      final a = await _encrypt(
        _payload(2500),
        recoveryKey: key,
        random: Random(3),
      );
      final b = await _encrypt(
        _payload(2500),
        recoveryKey: key,
        random: Random(3),
      );
      expect(a, b);
    });

    test('an empty passphrase is refused', () {
      final stream = BackupCodec(kdfParams: _fastKdf).encrypt(
        const Stream.empty(),
        passphrase: '',
        recoveryKey: RecoveryKey.generate(),
      );
      expect(_collect(stream), throwsArgumentError);
    });
  });

  group('wrong credentials', () {
    late Uint8List file;
    setUpAll(() async => file = await _encrypt(_payload(2000)));

    test('wrong passphrase', () {
      expect(
        BackupCodec().unlock(
          _pieces(file),
          const PassphraseCredential('mvua ya asubuhi 2026'),
        ),
        throwsA(isA<WrongBackupCredentialException>()),
      );
    });

    test('wrong recovery key', () {
      expect(
        BackupCodec().unlock(
          _pieces(file),
          RecoveryKeyCredential(RecoveryKey.generate()),
        ),
        throwsA(isA<WrongBackupCredentialException>()),
      );
    });
  });

  group('integrity', () {
    late Uint8List file;
    late UnlockedBackup unlocked;
    setUpAll(() async {
      file = await _encrypt(_payload(3 * _chunk + 500));
      unlocked = await BackupCodec().unlock(
        _pieces(file),
        const PassphraseCredential(_passphrase),
      );
    });

    test('intact file verifies', () async {
      await expectLater(unlocked.verify(_pieces(file)), completes);
    });

    test('any flipped ciphertext byte is caught', () async {
      for (final offset in [
        0,
        1,
        _chunk,
        _chunk + _tag,
        file.length - _headerLength - 1,
      ]) {
        final tampered = Uint8List.fromList(file)
          ..[_headerLength + offset] ^= 0x80;
        await expectLater(
          unlocked.verify(_pieces(tampered)),
          throwsA(isA<BackupTamperedException>()),
          reason: 'payload offset $offset',
        );
      }
    });

    test('a header field changed with a fixed-up checksum is caught', () async {
      // The salt is bound into the key wraps: unlocking fails.
      final saltEdit = Uint8List.fromList(file)..[30] ^= 0x01;
      await expectLater(
        BackupCodec().unlock(
          _pieces(_withChecksum(saltEdit)),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<WrongBackupCredentialException>()),
      );
      // The recovery wrap does not affect a passphrase unlock, but every
      // chunk is bound to the whole header.
      final wrapEdit = _withChecksum(Uint8List.fromList(file)..[130] ^= 0x01);
      final reopened = await BackupCodec().unlock(
        _pieces(wrapEdit),
        const PassphraseCredential(_passphrase),
      );
      await expectLater(
        reopened.verify(_pieces(wrapEdit)),
        throwsA(isA<BackupTamperedException>()),
      );
    });

    test('a header damaged without a fixed-up checksum is caught', () async {
      final damaged = Uint8List.fromList(file)..[50] ^= 0x01;
      await expectLater(
        BackupCodec().unlock(
          _pieces(damaged),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<BackupTamperedException>()),
      );
    });

    test('decrypting a different file than the one unlocked fails', () async {
      final other = await _encrypt(_payload(100));
      await expectLater(
        unlocked.verify(_pieces(other)),
        throwsA(isA<BackupTamperedException>()),
      );
    });

    test('a file cut at a chunk boundary is reported as truncated', () async {
      for (final chunks in [0, 1, 2]) {
        final cut = file.sublist(0, _headerLength + chunks * (_chunk + _tag));
        await expectLater(
          unlocked.verify(_pieces(cut)),
          throwsA(isA<BackupTruncatedException>()),
          reason: '$chunks chunks kept',
        );
      }
    });

    test('a file cut inside a chunk fails the integrity check', () async {
      for (final length in [
        _headerLength + 5,
        _headerLength + 500,
        file.length - 1,
      ]) {
        await expectLater(
          unlocked.verify(_pieces(file.sublist(0, length))),
          throwsA(isA<BackupIntegrityException>()),
          reason: 'length $length',
        );
      }
    });

    test('a file cut inside the header is reported as truncated', () async {
      await expectLater(
        BackupCodec().unlock(
          _pieces(file.sublist(0, 150)),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<BackupTruncatedException>()),
      );
    });

    test('trailing bytes are rejected', () async {
      final extended = Uint8List.fromList([...file, 0]);
      await expectLater(
        unlocked.verify(_pieces(extended)),
        throwsA(isA<BackupTamperedException>()),
      );
    });

    test('swapped chunks are rejected', () async {
      const block = _chunk + _tag;
      final swapped = Uint8List.fromList(file)
        ..setRange(
          _headerLength,
          _headerLength + block,
          file,
          _headerLength + block,
        )
        ..setRange(
          _headerLength + block,
          _headerLength + 2 * block,
          file,
          _headerLength,
        );
      await expectLater(
        unlocked.verify(_pieces(swapped)),
        throwsA(isA<BackupTamperedException>()),
      );
    });
  });

  group('header checks on unlock', () {
    late Uint8List file;
    setUpAll(() async => file = await _encrypt(_payload(10)));

    test('a newer format version is refused before any key derivation', () {
      final newer = Uint8List.fromList(file)..[9] = 2;
      expect(
        BackupCodec().unlock(
          _pieces(newer),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(
          isA<UnsupportedBackupVersionException>().having(
            (e) => e.version,
            'version',
            2,
          ),
        ),
      );
    });

    test('something that is not a backup is refused', () {
      expect(
        BackupCodec().unlock(
          Stream.value('PK zip archive, not a backup'.codeUnits),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<NotABackupFileException>()),
      );
      expect(
        BackupCodec().unlock(
          const Stream.empty(),
          const PassphraseCredential(_passphrase),
        ),
        throwsA(isA<NotABackupFileException>()),
      );
    });
  });
}
