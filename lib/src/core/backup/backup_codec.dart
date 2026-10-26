import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_exceptions.dart';
import 'backup_header.dart';
import 'recovery_key.dart';

/// What the user offers to open a backup.
sealed class BackupCredential {
  const BackupCredential();
}

final class PassphraseCredential extends BackupCredential {
  const PassphraseCredential(this.passphrase);

  final String passphrase;

  @override
  String toString() => 'PassphraseCredential(redacted)';
}

final class RecoveryKeyCredential extends BackupCredential {
  const RecoveryKeyCredential(this.recoveryKey);

  final RecoveryKey recoveryKey;
}

/// Writes and reads `.pcbackup` files.
///
/// A random 256-bit data key encrypts the payload with AES-256-GCM in
/// chunks. That data key is wrapped twice in the header: once under a key
/// derived from the passphrase with Argon2id, once under a key derived from
/// the [RecoveryKey] with HKDF-SHA256. Either one unlocks the file.
///
/// Each chunk's 12-byte nonce is the file's 7-byte random prefix, a 4-byte
/// chunk counter and a final-chunk flag, so chunks cannot be reordered,
/// dropped from the end or moved between files without failing
/// authentication. Memory use is about one chunk, whatever the payload size.
///
/// Streams are single-use: pass a fresh one (for example `file.openRead()`)
/// to each call.
final class BackupCodec {
  /// [random] exists for deterministic tests; production code must leave it
  /// unset so a secure source is used.
  BackupCodec({
    this.kdfParams = KdfParams.recommended,
    this.chunkSize = BackupHeader.defaultChunkSize,
    Random? random,
  }) : _random = random ?? Random.secure();

  final KdfParams kdfParams;
  final int chunkSize;
  final Random _random;

  static final _aes = AesGcm.with256bits();
  static final _recoveryInfo = utf8.encode('pcbackup v1 recovery key wrap');

  /// Encrypts [payload] into a complete `.pcbackup` byte stream.
  Stream<List<int>> encrypt(
    Stream<List<int>> payload, {
    required String passphrase,
    required RecoveryKey recoveryKey,
  }) async* {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    final dataKey = SecretKeyData(_randomBytes(BackupHeader.keyLength));
    final salt = _randomBytes(BackupHeader.saltLength);
    final unwrapped = BackupHeader(
      kdfParams: kdfParams,
      salt: salt,
      chunkSize: chunkSize,
      noncePrefix: _randomBytes(BackupHeader.noncePrefixLength),
      passphraseWrapNonce: _randomBytes(BackupHeader.nonceLength),
      passphraseWrappedKey: Uint8List(BackupHeader.wrappedKeyLength),
      recoveryWrapNonce: _randomBytes(BackupHeader.nonceLength),
      recoveryWrappedKey: Uint8List(BackupHeader.wrappedKeyLength),
    );
    final aad = unwrapped.wrapAad();
    final passphraseKek = await _passphraseKek(passphrase, kdfParams, salt);
    final recoveryKek = await _recoveryKek(recoveryKey, salt);
    final header = BackupHeader(
      kdfParams: kdfParams,
      salt: salt,
      chunkSize: chunkSize,
      noncePrefix: unwrapped.noncePrefix,
      passphraseWrapNonce: unwrapped.passphraseWrapNonce,
      passphraseWrappedKey: await _seal(
        dataKey.bytes,
        passphraseKek,
        unwrapped.passphraseWrapNonce,
        aad,
      ),
      recoveryWrapNonce: unwrapped.recoveryWrapNonce,
      recoveryWrappedKey: await _seal(
        dataKey.bytes,
        recoveryKek,
        unwrapped.recoveryWrapNonce,
        aad,
      ),
    );
    final headerBytes = header.toBytes();
    yield headerBytes;

    final pending = BytesBuilder(copy: false);
    var counter = 0;
    await for (final piece in payload) {
      pending.add(piece);
      // Strictly greater: a full chunk is only known not to be the last once
      // at least one more byte has arrived.
      if (pending.length > chunkSize) {
        final bytes = pending.takeBytes();
        var offset = 0;
        while (bytes.length - offset > chunkSize) {
          yield await _seal(
            Uint8List.sublistView(bytes, offset, offset + chunkSize),
            dataKey,
            _chunkNonce(header.noncePrefix, counter++, isFinal: false),
            headerBytes,
          );
          offset += chunkSize;
        }
        pending.add(Uint8List.sublistView(bytes, offset));
      }
    }
    yield await _seal(
      pending.takeBytes(),
      dataKey,
      _chunkNonce(header.noncePrefix, counter, isFinal: true),
      headerBytes,
    );
  }

  /// Reads the header from [file] and unwraps the data key.
  ///
  /// Throws [WrongBackupCredentialException] if [credential] does not fit,
  /// or another [BackupException] if the header is unusable. Only the header
  /// is read; call [UnlockedBackup.verify] before restoring anything.
  Future<UnlockedBackup> unlock(
    Stream<List<int>> file,
    BackupCredential credential,
  ) async {
    final reader = _ByteReader(file);
    final BackupHeader header;
    final Uint8List headerBytes;
    try {
      (header, headerBytes) = await _readHeader(reader);
    } finally {
      await reader.cancel();
    }
    final kek = switch (credential) {
      PassphraseCredential(:final passphrase) => await _passphraseKek(
        passphrase,
        header.kdfParams,
        header.salt,
      ),
      RecoveryKeyCredential(:final recoveryKey) => await _recoveryKek(
        recoveryKey,
        header.salt,
      ),
    };
    final (nonce, wrapped) = switch (credential) {
      PassphraseCredential() => (
        header.passphraseWrapNonce,
        header.passphraseWrappedKey,
      ),
      RecoveryKeyCredential() => (
        header.recoveryWrapNonce,
        header.recoveryWrappedKey,
      ),
    };
    final List<int> dataKey;
    try {
      dataKey = await _open(wrapped, kek, nonce, header.wrapAad());
    } on SecretBoxAuthenticationError {
      throw const WrongBackupCredentialException();
    }
    return UnlockedBackup._(header, headerBytes, SecretKeyData(dataKey));
  }

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  static Future<SecretKey> _passphraseKek(
    String passphrase,
    KdfParams params,
    List<int> salt,
  ) {
    return Argon2id(
      parallelism: params.parallelism,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: BackupHeader.keyLength,
    ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);
  }

  static Future<SecretKey> _recoveryKek(RecoveryKey key, List<int> salt) {
    return Hkdf(
      hmac: Hmac.sha256(),
      outputLength: BackupHeader.keyLength,
    ).deriveKey(
      secretKey: SecretKey(key.bytes),
      nonce: salt,
      info: _recoveryInfo,
    );
  }
}

/// A backup whose data key is known; decrypts the file it was unlocked from.
final class UnlockedBackup {
  UnlockedBackup._(this.header, this._headerBytes, this._dataKey);

  final BackupHeader header;
  final Uint8List _headerBytes;
  final SecretKey _dataKey;

  /// Authenticates every chunk of [file] without keeping any plaintext.
  ///
  /// Completes normally only if the whole file is intact.
  Future<void> verify(Stream<List<int>> file) => decrypt(file).drain<void>();

  /// Decrypts the payload of [file], one authenticated chunk at a time.
  ///
  /// Each emitted chunk is authentic, but a file cut short at a chunk
  /// boundary is only detected at the end, so callers must stage the output
  /// and commit it only once this stream completes without error.
  Stream<List<int>> decrypt(Stream<List<int>> file) async* {
    final reader = _ByteReader(file);
    try {
      final (_, headerBytes) = await _readHeader(reader);
      for (var i = 0; i < headerBytes.length; i++) {
        if (headerBytes[i] != _headerBytes[i]) {
          throw const BackupTamperedException(
            'The header differs from the one that was unlocked.',
          );
        }
      }
      final fullBlock = header.chunkSize + BackupHeader.tagLength;
      var counter = 0;
      while (true) {
        final block = await reader.read(fullBlock);
        final isFinal = block.length < fullBlock || await reader.isAtEnd;
        if (block.length < BackupHeader.tagLength) {
          throw block.isEmpty
              ? const BackupTruncatedException()
              : const BackupTamperedException('A chunk is too short.');
        }
        yield await _openChunk(block, counter, isFinal: isFinal);
        if (isFinal) return;
        counter++;
      }
    } finally {
      await reader.cancel();
    }
  }

  Future<List<int>> _openChunk(
    Uint8List block,
    int counter, {
    required bool isFinal,
  }) async {
    try {
      return await _open(
        block,
        _dataKey,
        _chunkNonce(header.noncePrefix, counter, isFinal: isFinal),
        _headerBytes,
      );
    } on SecretBoxAuthenticationError {
      if (isFinal) {
        // An intact non-final chunk at the end means the rest was cut off.
        try {
          await _open(
            block,
            _dataKey,
            _chunkNonce(header.noncePrefix, counter, isFinal: false),
            _headerBytes,
          );
          throw const BackupTruncatedException();
        } on SecretBoxAuthenticationError {
          // Fall through to the tamper report.
        }
      }
      throw BackupTamperedException('Chunk $counter failed authentication.');
    }
  }
}

Future<(BackupHeader, Uint8List)> _readHeader(_ByteReader reader) async {
  final preamble = await reader.read(BackupHeader.preambleLength);
  BackupHeader.checkPreamble(preamble);
  final rest = await reader.read(
    BackupHeader.length - BackupHeader.preambleLength,
  );
  final bytes = Uint8List(preamble.length + rest.length)
    ..setAll(0, preamble)
    ..setAll(preamble.length, rest);
  return (BackupHeader.parse(bytes), bytes);
}

Uint8List _chunkNonce(List<int> prefix, int counter, {required bool isFinal}) {
  if (counter > 0xffffffff) {
    throw StateError('Backup payload has too many chunks.');
  }
  final nonce = Uint8List(BackupHeader.nonceLength)..setAll(0, prefix);
  ByteData.sublistView(nonce)
      .setUint32(BackupHeader.noncePrefixLength, counter);
  nonce[BackupHeader.nonceLength - 1] = isFinal ? 1 : 0;
  return nonce;
}

/// AES-256-GCM encrypt, returning ciphertext followed by the 16-byte tag.
Future<Uint8List> _seal(
  List<int> clearText,
  SecretKey key,
  List<int> nonce,
  List<int> aad,
) async {
  final box = await BackupCodec._aes.encrypt(
    clearText,
    secretKey: key,
    nonce: nonce,
    aad: aad,
  );
  return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
}

Future<List<int>> _open(
  Uint8List sealed,
  SecretKey key,
  List<int> nonce,
  List<int> aad,
) {
  final split = sealed.length - BackupHeader.tagLength;
  return BackupCodec._aes.decrypt(
    SecretBox(
      Uint8List.sublistView(sealed, 0, split),
      nonce: nonce,
      mac: Mac(Uint8List.sublistView(sealed, split)),
    ),
    secretKey: key,
    aad: aad,
  );
}

/// Reads exact byte counts from a stream of arbitrarily sized pieces.
final class _ByteReader {
  _ByteReader(Stream<List<int>> source) : _source = StreamIterator(source);

  final StreamIterator<List<int>> _source;
  List<int> _current = const [];
  int _offset = 0;

  /// Returns [count] bytes, or fewer if the stream ends first.
  Future<Uint8List> read(int count) async {
    final out = BytesBuilder(copy: false);
    while (out.length < count) {
      if (_offset >= _current.length && !await _advance()) break;
      final take = min(count - out.length, _current.length - _offset);
      out.add(_current.sublist(_offset, _offset + take));
      _offset += take;
    }
    return out.takeBytes();
  }

  Future<bool> get isAtEnd async =>
      _offset >= _current.length && !await _advance();

  Future<bool> _advance() async {
    while (await _source.moveNext()) {
      _current = _source.current;
      _offset = 0;
      if (_current.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> cancel() => _source.cancel();
}
