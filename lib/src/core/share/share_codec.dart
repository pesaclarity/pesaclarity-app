import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Why a `.pcshare` file or an invite could not be read.
class ShareFileException implements Exception {
  const ShareFileException(this.reason);

  final String reason;

  @override
  String toString() => 'ShareFileException: $reason';
}

/// What a QR code or a small `.pcshare` file can hold besides an update.
enum ShareCodeKind { joinRequest, invite }

/// The kind of [text], read and checked the same way whether it came from
/// the camera or a file. Throws [ShareFileException] for anything else.
ShareCodeKind readShareCode(String text) {
  final codec = ShareCodec();
  final trimmed = text.trim();
  if (trimmed.startsWith(ShareCodec.joinPrefix)) {
    codec.openJoinRequest(trimmed);
    return ShareCodeKind.joinRequest;
  }
  if (trimmed.startsWith(ShareCodec.invitePrefix)) {
    final body = codec.readInvite(trimmed);
    for (final key in [
      'space',
      'name',
      'kind',
      'ownerKey',
      'wrap',
      'owner',
      'you',
    ]) {
      if (body[key] == null) throw const ShareFileException('invite');
    }
    return ShareCodeKind.invite;
  }
  throw const ShareFileException('not a Pesa Clarity code');
}

/// A member's key pair: an X25519 private key kept as its 32-byte seed.
class ShareKeyPair {
  const ShareKeyPair(this.seed, this.publicKey);

  final List<int> seed;
  final List<int> publicKey;

  static Future<ShareKeyPair> fromSeed(List<int> seed) async {
    final pair = await X25519().newKeyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    return ShareKeyPair(List.unmodifiable(seed), pub.bytes);
  }

  static Future<ShareKeyPair> generate([Random? random]) =>
      fromSeed(randomBytes(32, random));
}

List<int> randomBytes(int n, [Random? random]) {
  final r = random ?? Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

/// The outside of a `.pcshare` file: who it is from and for. Read before
/// the file is opened, and bound into its authentication, so none of it
/// can be changed.
class ShareFileHeader {
  const ShareFileHeader({
    required this.space,
    required this.file,
    required this.from,
    required this.to,
    required this.epoch,
    required this.at,
    this.rekeyNonce,
    this.rekeyWrapped,
  });

  /// The shared space's random id.
  final String space;

  /// This file's id: a file opened twice is skipped.
  final String file;
  final String from;
  final String to;

  /// Which space key sealed it. It goes up each time the key is replaced.
  final int epoch;
  final DateTime at;

  /// The new space key, sealed to the recipient, when the Owner replaced it
  /// (after removing someone).
  final List<int>? rekeyNonce;
  final List<int>? rekeyWrapped;

  Map<String, Object?> toJson() => {
    'space': space,
    'file': file,
    'from': from,
    'to': to,
    'epoch': epoch,
    'at': at.toUtc().toIso8601String(),
    if (rekeyNonce != null) 'rn': base64Url.encode(rekeyNonce!),
    if (rekeyWrapped != null) 'rk': base64Url.encode(rekeyWrapped!),
  };

  static ShareFileHeader fromJson(Object? json) {
    if (json is! Map) throw const ShareFileException('header');
    try {
      return ShareFileHeader(
        space: json['space']! as String,
        file: json['file']! as String,
        from: json['from']! as String,
        to: json['to']! as String,
        epoch: json['epoch']! as int,
        at: DateTime.parse(json['at']! as String),
        rekeyNonce: json['rn'] == null
            ? null
            : base64Url.decode(json['rn']! as String),
        rekeyWrapped: json['rk'] == null
            ? null
            : base64Url.decode(json['rk']! as String),
      );
    } on Object {
      throw const ShareFileException('header');
    }
  }
}

/// An opened file: its header, the space key it was sealed with (new when
/// it carried one), and what it held.
class OpenedShareFile {
  const OpenedShareFile(this.header, this.spaceKey, this.payload);

  final ShareFileHeader header;
  final List<int> spaceKey;
  final Map<String, Object?> payload;
}

/// Writes and reads `.pcshare` update files and invites (decision 0031,
/// stage 1). No server is involved; the file goes by WhatsApp, email or
/// Bluetooth.
///
/// The same primitives as the vault's `.pcbackup`, from the same
/// `cryptography` package: AES-256-GCM, HKDF-SHA256, plus X25519 for
/// members' key pairs.
///
/// A file is `PCSHARE`, a version byte, the header's length (2 bytes) and
/// its JSON, a 12-byte nonce, then the gzipped JSON payload sealed with
/// AES-256-GCM. The key is HKDF over the space key and the X25519 secret of
/// the sender's and recipient's key pairs, salted with the file id; the
/// header is the associated data. So a file opens only for its recipient,
/// only with the space key, only from the member it names, and any change
/// to header or body fails authentication.
final class ShareCodec {
  ShareCodec({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  static const version = 1;
  static const _magic = 'PCSHARE';
  static const invitePrefix = 'pcshare-invite:2:';
  static const joinPrefix = 'pcshare-join:1:';
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _x25519 = X25519();

  /// A new random space key.
  List<int> newSpaceKey() => randomBytes(32, _random);

  Future<List<int>> _shared(List<int> mySeed, List<int> theirPublic) async {
    final pair = await _x25519.newKeyPairFromSeed(mySeed);
    final secret = await _x25519.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519),
    );
    return secret.extractBytes();
  }

  Future<SecretKey> _derive(List<int> ikm, String salt, String info) =>
      _hkdf.deriveKey(
        secretKey: SecretKeyData(ikm),
        nonce: utf8.encode(salt),
        info: utf8.encode(info),
      );

  /// Seals [payload] from the holder of [mySeed] to [theirPublic].
  /// With [newSpaceKey], the file is sealed with it and carries it, sealed
  /// to the recipient alone; [header]'s epoch must be the new key's.
  Future<Uint8List> seal({
    required ShareFileHeader header,
    required List<int> spaceKey,
    required List<int> mySeed,
    required List<int> theirPublic,
    required Map<String, Object?> payload,
    bool carryKey = false,
  }) async {
    final dh = await _shared(mySeed, theirPublic);
    var h = header;
    if (carryKey) {
      final nonce = randomBytes(12, _random);
      final wrapKey = await _derive(dh, header.file, 'pcshare v1 rekey');
      final box = await _aes.encrypt(
        spaceKey,
        secretKey: wrapKey,
        nonce: nonce,
        aad: utf8.encode('rekey|${header.space}|${header.epoch}'),
      );
      h = ShareFileHeader(
        space: header.space,
        file: header.file,
        from: header.from,
        to: header.to,
        epoch: header.epoch,
        at: header.at,
        rekeyNonce: nonce,
        rekeyWrapped: box.concatenation(nonce: false),
      );
    }
    final headerBytes = utf8.encode(jsonEncode(h.toJson()));
    final out = BytesBuilder()
      ..add(ascii.encode(_magic))
      ..addByte(version)
      ..add([headerBytes.length >> 8, headerBytes.length & 0xff])
      ..add(headerBytes);
    final aad = out.toBytes();
    final nonce = randomBytes(12, _random);
    final key = await _derive([...spaceKey, ...dh], h.file, 'pcshare v1 file');
    final box = await _aes.encrypt(
      gzip.encode(utf8.encode(jsonEncode(payload))),
      secretKey: key,
      nonce: nonce,
      aad: aad,
    );
    out.add(box.concatenation());
    return out.toBytes();
  }

  /// The header of [bytes], without opening it.
  ShareFileHeader readHeader(List<int> bytes) => _split(bytes).$1;

  (ShareFileHeader, List<int>, List<int>) _split(List<int> bytes) {
    if (bytes.length < 10 ||
        ascii.decode(bytes.sublist(0, 7), allowInvalid: true) != _magic) {
      throw const ShareFileException('not a .pcshare file');
    }
    if (bytes[7] != version) {
      throw const ShareFileException('made by a newer app');
    }
    final length = (bytes[8] << 8) | bytes[9];
    if (bytes.length < 10 + length + 12 + 16) {
      throw const ShareFileException('cut short');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes.sublist(10, 10 + length)));
    } on FormatException {
      throw const ShareFileException('header');
    }
    return (
      ShareFileHeader.fromJson(json),
      bytes.sublist(0, 10 + length),
      bytes.sublist(10 + length),
    );
  }

  /// Opens [bytes]. [keyFor] gives the space key of an epoch this phone
  /// has. Throws [ShareFileException] when anything does not check out.
  Future<OpenedShareFile> open(
    List<int> bytes, {
    required List<int>? Function(int epoch) keyFor,
    required List<int> mySeed,
    required List<int> theirPublic,
  }) async {
    final (header, aad, rest) = _split(bytes);
    final dh = await _shared(mySeed, theirPublic);
    var spaceKey = keyFor(header.epoch);
    if (header.rekeyWrapped case final wrapped?) {
      try {
        final wrapKey = await _derive(dh, header.file, 'pcshare v1 rekey');
        spaceKey = await _aes.decrypt(
          SecretBox.fromConcatenation(
            [...header.rekeyNonce!, ...wrapped],
            nonceLength: 12,
            macLength: 16,
          ),
          secretKey: wrapKey,
          aad: utf8.encode('rekey|${header.space}|${header.epoch}'),
        );
      } on SecretBoxAuthenticationError {
        throw const ShareFileException('wrong key');
      }
    }
    if (spaceKey == null) throw const ShareFileException('wrong key');
    final key = await _derive(
      [...spaceKey, ...dh],
      header.file,
      'pcshare v1 file',
    );
    final List<int> plain;
    try {
      plain = await _aes.decrypt(
        SecretBox.fromConcatenation(rest, nonceLength: 12, macLength: 16),
        secretKey: key,
        aad: aad,
      );
    } on SecretBoxAuthenticationError {
      throw const ShareFileException('wrong key or changed');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(plain)));
    } on Object {
      throw const ShareFileException('payload');
    }
    if (json is! Map<String, Object?>) {
      throw const ShareFileException('payload');
    }
    return OpenedShareFile(header, spaceKey, json);
  }

  /// A join request, made on the invitee's phone: their name and public
  /// key. Their private key never leaves that phone.
  String joinRequest({
    required String name,
    required List<int> publicKey,
    List<int>? signKey,
  }) =>
      '$joinPrefix${base64Url.encode(utf8.encode(jsonEncode({'name': name, 'key': base64Url.encode(publicKey), if (signKey != null) 'sign': base64Url.encode(signKey)})))}';

  /// The signing key in a join request, which the member's answers to
  /// waiting changes are checked with; null in an older request.
  List<int>? joinSignKey(String text) {
    try {
      final body = jsonDecode(
        utf8.decode(base64Url.decode(text.trim().substring(joinPrefix.length))),
      ) as Map<String, Object?>;
      final sign = body['sign'];
      if (sign is! String) return null;
      final key = base64Url.decode(sign);
      return key.length == 32 ? key : null;
    } on Object {
      return null;
    }
  }

  /// The name and public key in a join request.
  (String, List<int>) openJoinRequest(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(joinPrefix)) {
      throw const ShareFileException('not a join request');
    }
    try {
      final body = jsonDecode(
        utf8.decode(base64Url.decode(trimmed.substring(joinPrefix.length))),
      ) as Map<String, Object?>;
      final key = base64Url.decode(body['key']! as String);
      if (key.length != 32) throw const FormatException('key');
      return (body['name']! as String, key);
    } on Object {
      throw const ShareFileException('join request');
    }
  }

  /// An invite, made by the Owner from a join request: the space key
  /// sealed to the invitee's own public key (X25519 and HKDF), so only the
  /// phone that made the request can open it.
  Future<String> invite({
    required ShareKeyPair owner,
    required List<int> inviteePublicKey,
    required List<int> spaceKey,
    required Map<String, Object?> details,
  }) async {
    final dh = await _shared(owner.seed, inviteePublicKey);
    final nonce = randomBytes(12, _random);
    final wrapKey = await _derive(dh, 'invite', 'pcshare v1 invite');
    final box = await _aes.encrypt(
      spaceKey,
      secretKey: wrapKey,
      nonce: nonce,
      aad: utf8.encode('invite|${details['space']}'),
    );
    final body = {
      ...details,
      'ownerKey': base64Url.encode(owner.publicKey),
      'wrap': base64Url.encode(box.concatenation()),
    };
    return '$invitePrefix${base64Url.encode(utf8.encode(jsonEncode(body)))}';
  }

  /// An invite's details, readable by anyone who has it; the space key
  /// is not among them.
  Map<String, Object?> readInvite(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith(invitePrefix)) {
      throw const ShareFileException('not an invite');
    }
    try {
      return jsonDecode(
        utf8.decode(base64Url.decode(trimmed.substring(invitePrefix.length))),
      ) as Map<String, Object?>;
    } on Object {
      throw const ShareFileException('invite');
    }
  }

  /// Opens an invite with the key pair that made the join request: its
  /// details and the space key.
  Future<(Map<String, Object?>, List<int>)> openInvite(
    String text,
    ShareKeyPair mine,
  ) async {
    final body = readInvite(text);
    try {
      final ownerKey = base64Url.decode(body['ownerKey']! as String);
      final dh = await _shared(mine.seed, ownerKey);
      final wrapKey = await _derive(dh, 'invite', 'pcshare v1 invite');
      final key = await _aes.decrypt(
        SecretBox.fromConcatenation(
          base64Url.decode(body['wrap']! as String),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: wrapKey,
        aad: utf8.encode('invite|${body['space']}'),
      );
      return (body, key);
    } on Object {
      throw const ShareFileException('invite');
    }
  }
}

/// Signs and checks a member's answers to waiting changes (Ed25519). The
/// signing key comes from the member's own seed, so it never leaves the
/// phone; its public half is in the space's member list.
abstract final class ShareSigner {
  static final _ed = Ed25519();

  static Future<SimpleKeyPair> _pair(List<int> seed) async {
    final h = await Sha256().hash([
      ...utf8.encode('pcshare v1 sign|'),
      ...seed,
    ]);
    return _ed.newKeyPairFromSeed(h.bytes);
  }

  static Future<List<int>> publicKey(List<int> seed) async =>
      (await (await _pair(seed)).extractPublicKey()).bytes;

  static Future<List<int>> sign(List<int> seed, String message) async {
    final sig = await _ed.sign(
      utf8.encode(message),
      keyPair: await _pair(seed),
    );
    return sig.bytes;
  }

  static Future<bool> verify(
    List<int>? publicKey,
    String message,
    Object? signature,
  ) async {
    if (publicKey == null || publicKey.length != 32 || signature is! String) {
      return false;
    }
    try {
      return await _ed.verify(
        utf8.encode(message),
        signature: Signature(
          base64Url.decode(signature),
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
