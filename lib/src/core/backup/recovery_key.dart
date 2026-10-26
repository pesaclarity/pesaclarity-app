import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'backup_exceptions.dart';

/// A random 256-bit key the user writes down or prints at backup setup.
///
/// It unlocks a backup on its own when the passphrase is lost. It is shown
/// as 56 Crockford base32 characters in 14 groups of four: the 32 key bytes
/// followed by a 3-byte SHA-256 checksum, so typos are caught before any
/// decryption is attempted.
final class RecoveryKey {
  RecoveryKey._(this._bytes);

  /// Wraps existing key bytes, for example when reading from secure storage.
  factory RecoveryKey.fromBytes(List<int> bytes) {
    if (bytes.length != keyLength) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'A recovery key is $keyLength bytes',
      );
    }
    return RecoveryKey._(Uint8List.fromList(bytes));
  }

  /// Generates a new key from a cryptographically secure source.
  factory RecoveryKey.generate([Random? random]) {
    final source = random ?? Random.secure();
    return RecoveryKey._(
      Uint8List.fromList(List.generate(keyLength, (_) => source.nextInt(256))),
    );
  }

  /// Parses the grouped form the user typed.
  ///
  /// Case, spaces and hyphens are ignored, and the look-alikes O, I and L
  /// are read as 0, 1 and 1.
  factory RecoveryKey.parse(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (cleaned.length != _encodedLength) {
      throw InvalidRecoveryKeyException(
        'A recovery key has $_encodedLength characters; '
        'found ${cleaned.length}.',
      );
    }
    final decoded = _base32Decode(cleaned);
    final key = Uint8List.sublistView(decoded, 0, keyLength);
    final checksum = Uint8List.sublistView(decoded, keyLength);
    final expected = _checksum(key);
    for (var i = 0; i < _checksumLength; i++) {
      if (checksum[i] != expected[i]) {
        throw const InvalidRecoveryKeyException(
          'The recovery key has a typo: its checksum does not match.',
        );
      }
    }
    return RecoveryKey._(Uint8List.fromList(key));
  }

  static const keyLength = 32;
  static const _checksumLength = 3;
  static const _groupLength = 4;
  // (32 + 3) bytes * 8 bits / 5 bits per character.
  static const _encodedLength = 56;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  final Uint8List _bytes;

  /// The raw key bytes. Callers must not keep copies longer than needed.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// The grouped form shown to the user, e.g. `7K3M-…-Q9ZD`.
  String toDisplayString() {
    final encoded = _base32Encode(
      Uint8List.fromList([..._bytes, ..._checksum(_bytes)]),
    );
    final groups = <String>[
      for (var i = 0; i < encoded.length; i += _groupLength)
        encoded.substring(i, i + _groupLength),
    ];
    return groups.join('-');
  }

  @override
  bool operator ==(Object other) {
    if (other is! RecoveryKey) return false;
    var diff = 0;
    for (var i = 0; i < keyLength; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  /// Never prints the key, so it cannot leak into logs.
  @override
  String toString() => 'RecoveryKey(redacted)';

  static List<int> _checksum(List<int> key) =>
      const DartSha256().hashSync(key).bytes.sublist(0, _checksumLength);

  static String _base32Encode(Uint8List data) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    assert(bits == 0, 'input length must be a multiple of 5 bytes');
    return out.toString();
  }

  static Uint8List _base32Decode(String text) {
    final out = BytesBuilder(copy: false);
    var buffer = 0;
    var bits = 0;
    for (final char in text.split('')) {
      final value = _alphabet.indexOf(switch (char) {
        'O' => '0',
        'I' || 'L' => '1',
        _ => char,
      });
      if (value < 0) {
        throw InvalidRecoveryKeyException(
          '"$char" is not used in recovery keys.',
        );
      }
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
        buffer &= (1 << bits) - 1;
      }
    }
    return out.takeBytes();
  }
}
