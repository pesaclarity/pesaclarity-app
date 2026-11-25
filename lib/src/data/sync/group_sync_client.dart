import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../../core/share/share_codec.dart';

/// Group sync through our server (decision 0033). Off until licences exist:
/// it is a paid feature for the space's owner (0032). Build with
/// `--dart-define=GROUP_SYNC=true` to try it.
const bool groupSyncEnabled = bool.fromEnvironment('GROUP_SYNC');

/// Why the sync server said no, by its error code (`not_member`,
/// `read_only`, `licence_expired`, `rate_limited` ...).
class GroupSyncException implements Exception {
  const GroupSyncException(this.status, this.code);

  final int status;
  final String code;

  /// The owner's licence has run out: pulling still works, sending does not.
  bool get readOnly => code == 'read_only';
  bool get licenceProblem => status == 402 || code.startsWith('licence_');
  bool get removed => code == 'not_member';

  @override
  String toString() => 'GroupSyncException($status, $code)';
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

/// The sizes a batch is padded to, so its length says little: 1 KiB to 1 MiB.
final List<int> syncSizeSteps = [for (var i = 0; i <= 10; i++) 1024 << i];

/// A `.pcshare` file as it travels to the server: its length (4 bytes,
/// big-endian), the file, then zeros up to the next size step. The file's
/// own AES-GCM seal is untouched.
Uint8List padForSync(List<int> file) {
  final size = syncSizeSteps.firstWhere(
    (s) => s >= file.length + 4,
    orElse: () => throw ArgumentError('Update too big to sync'),
  );
  final out = Uint8List(size);
  ByteData.sublistView(out).setUint32(0, file.length);
  out.setRange(4, 4 + file.length, file);
  return out;
}

/// The `.pcshare` file inside a padded batch.
Uint8List unpadFromSync(List<int> batch) {
  if (batch.length < 4) throw const FormatException('Batch too short');
  final bytes = Uint8List.fromList(batch);
  final length = ByteData.sublistView(bytes).getUint32(0);
  if (length > bytes.length - 4) throw const FormatException('Bad batch');
  return Uint8List.sublistView(bytes, 4, 4 + length);
}

/// One batch from a pull: a padded `.pcshare` file and who sent it.
class SyncedBatch {
  const SyncedBatch({
    required this.cursor,
    required this.id,
    required this.from,
    required this.data,
  });

  final int cursor;
  final String id;

  /// The sender's signing key, as the server knows them.
  final String from;
  final List<int> data;
}

class SyncPull {
  const SyncPull(
    this.batches,
    this.next, {
    this.more = false,
    this.readOnly = false,
  });

  final List<SyncedBatch> batches;
  final int next;
  final bool more;
  final bool readOnly;
}

/// Talks to the sync server for one shared space. Each request is signed
/// with the member's Ed25519 key, derived from their share seed exactly as
/// [ShareSigner] does, so the server's member list is the space's signing
/// keys. The server only ever sees sealed `.pcshare` files.
class GroupSyncClient {
  GroupSyncClient({
    required this.server,
    required this.space,
    required List<int> seed,
    http.Client? httpClient,
    int Function()? nowMillis,
    Random? random,
  }) : _seed = List.unmodifiable(seed),
       _http = httpClient ?? http.Client(),
       _now = nowMillis ?? (() => DateTime.now().millisecondsSinceEpoch),
       _random = random ?? Random.secure();

  final Uri server;

  /// The shared space's random id, which names its cell.
  final String space;
  final List<int> _seed;
  final http.Client _http;
  final int Function() _now;
  final Random _random;

  static const protocol = 'pcsync v1';

  /// This member's key on the server: their signing key, base64url.
  Future<String> myKey() async => _b64(await ShareSigner.publicKey(_seed));

  /// The server's key for a member with [signKey].
  static String keyOf(List<int> signKey) => _b64(signKey);

  String get _base => '/v1/spaces/$space';

  Future<Map<String, String>> _sign(
    String method,
    String pathAndQuery,
    List<int> body,
  ) async {
    final time = '${_now()}';
    final nonce = _b64(randomBytes(16, _random));
    final hash = _b64((await Sha256().hash(body)).bytes);
    final message = [
      protocol,
      method,
      pathAndQuery,
      time,
      nonce,
      hash,
    ].join('\n');
    return {
      'x-pc-key': await myKey(),
      'x-pc-time': time,
      'x-pc-nonce': nonce,
      'x-pc-sig': _b64(await ShareSigner.sign(_seed, message)),
    };
  }

  Future<Map<String, Object?>> _call(
    String method,
    String path, {
    List<int> body = const [],
    Map<String, String> headers = const {},
  }) async {
    final uri = server.resolve(path);
    final signed = await _sign(
      method,
      uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
      body,
    );
    final request = http.Request(method, uri)
      ..headers.addAll({...signed, ...headers})
      ..bodyBytes = body;
    final response = await http.Response.fromStream(await _http.send(request));
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    final map = json is Map<String, Object?> ? json : const <String, Object?>{};
    if (response.statusCode >= 400) {
      throw GroupSyncException(
        response.statusCode,
        map['error'] as String? ?? 'http_${response.statusCode}',
      );
    }
    return map;
  }

  List<int> _json(Map<String, Object?> body) => utf8.encode(jsonEncode(body));

  /// Owner: makes the space on the server with their licence.
  Future<void> createSpace(String licence) =>
      _call('POST', _base, body: _json({'licence': licence}));

  /// Owner: a new licence after renewal.
  Future<void> renewLicence(String licence) =>
      _call('PUT', '$_base/licence', body: _json({'licence': licence}));

  /// Owner: lets the member with [signKey] sync. Returns the cursor they
  /// start from.
  Future<int> addMember(List<int> signKey) async =>
      (await _call('PUT', '$_base/members/${keyOf(signKey)}'))['cursor']
          as int? ??
      0;

  /// Owner: stops the member with [signKey] from syncing.
  Future<void> removeMember(List<int> signKey) =>
      _call('DELETE', '$_base/members/${keyOf(signKey)}');

  /// Owner: deletes the space and everything the server holds for it.
  Future<void> deleteSpace() => _call('DELETE', _base);

  /// Sends one `.pcshare` file, padded, to the member with [toSignKey] (or
  /// to everyone). Sending the same [batchId] again is harmless.
  Future<int> push(
    String batchId,
    List<int> pcshare, {
    List<int>? toSignKey,
  }) async {
    final r = await _call(
      'POST',
      '$_base/batches',
      body: padForSync(pcshare),
      headers: {
        'x-pc-batch': batchId,
        if (toSignKey != null) 'x-pc-to': keyOf(toSignKey),
      },
    );
    return r['cursor']! as int;
  }

  /// What is waiting for this member after [since].
  Future<SyncPull> pull(int since) async {
    final r = await _call('GET', '$_base/batches?since=$since');
    final batches = [
      for (final b
          in (r['batches'] as List? ?? const []).cast<Map<String, Object?>>())
        SyncedBatch(
          cursor: b['cursor']! as int,
          id: b['id']! as String,
          from: b['from']! as String,
          data: _unb64(b['data']! as String),
        ),
    ];
    return SyncPull(
      batches,
      r['next'] as int? ?? since,
      more: r['more'] == true,
      readOnly: r['readOnly'] == true,
    );
  }

  void close() => _http.close();
}
