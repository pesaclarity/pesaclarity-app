import 'dart:convert';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/features/backup/data/backup_location.dart';
import 'package:pesaclarity/src/features/backup/data/drive_client.dart';
import 'package:pesaclarity/src/features/backup/data/vault_client.dart';

class _Token implements VaultTokenSource {
  const _Token(this.token);

  final String? token;

  @override
  Future<String?> accessToken() async => token;
}

class _DriveAuth implements DriveAuth {
  @override
  bool get isAvailable => true;

  @override
  Future<String?> accessToken() async => 'drive-token';

  @override
  Future<String?> currentAccount() async => 'john@example.com';

  @override
  Future<String?> signIn() async => 'john@example.com';

  @override
  Future<void> signOut() async {}
}

String _sha(List<int> bytes) => [
  for (final b in const DartSha256().hashSync(bytes).bytes)
    b.toRadixString(16).padLeft(2, '0'),
].join();

void main() {
  late Directory dir;
  late File file;
  final bytes = List.generate(4000, (i) => i % 256);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('remote_locations_test');
    file = File(p.join(dir.path, 'b.pcbackup'))..writeAsBytesSync(bytes);
  });
  tearDown(() => dir.delete(recursive: true));

  group('VaultBackupLocation', () {
    final base = Uri.parse('https://vault.example.test/');

    test('uploads ciphertext with its checksum and bearer token', () async {
      late http.Request seen;
      final vault = VaultBackupLocation(
        baseUrl: base,
        tokens: const _Token('t0k'),
        client: MockClient((request) async {
          seen = request;
          return http.Response('{}', 201);
        }),
      );
      await vault.upload(file, 'b.pcbackup');
      expect(seen.method, 'POST');
      expect(
        seen.url.toString(),
        'https://vault.example.test/v1/vault/backups',
      );
      expect(seen.headers['Authorization'], 'Bearer t0k');
      expect(seen.headers['Content-Type'], 'application/octet-stream');
      expect(seen.headers['X-Content-SHA256'], _sha(bytes));
      expect(seen.bodyBytes, bytes);
    });

    test('lists backups newest first', () async {
      final vault = VaultBackupLocation(
        baseUrl: base,
        tokens: const _Token('t0k'),
        client: MockClient(
          (request) async => http.Response(
            jsonEncode([
              {
                'id': 'a',
                'size_bytes': 10,
                'sha256': 'x',
                'created_at': '2026-10-01T06:00:00Z',
              },
              {
                'id': 'b',
                'size_bytes': 12,
                'sha256': 'y',
                'created_at': '2026-10-20T06:00:00Z',
              },
            ]),
            200,
          ),
        ),
      );
      final entries = await vault.list();
      expect(entries.map((e) => e.id), ['b', 'a']);
      expect(entries.first.sizeBytes, 12);
    });

    test('downloads and checks the checksum', () async {
      VaultBackupLocation vaultReturning(String sha) => VaultBackupLocation(
        baseUrl: base,
        tokens: const _Token('t0k'),
        client: MockClient(
          (request) async => http.Response.bytes(
            bytes,
            200,
            headers: {'x-content-sha256': sha},
          ),
        ),
      );
      final entry = BackupEntry(
        id: 'b',
        name: 'Vault backup',
        createdAt: DateTime(2026),
      );
      final good = File(p.join(dir.path, 'good'));
      await vaultReturning(_sha(bytes)).download(entry, good);
      expect(good.readAsBytesSync(), bytes);

      final bad = File(p.join(dir.path, 'bad'));
      await expectLater(
        vaultReturning('0' * 64).download(entry, bad),
        throwsA(isA<BackupLocationException>()),
      );
      expect(bad.existsSync(), isFalse);
    });

    test('asks for sign-in when there is no token', () {
      final vault = VaultBackupLocation(
        baseUrl: base,
        tokens: const SignedOutVaultTokenSource(),
        client: MockClient((_) async => http.Response('', 200)),
      );
      expect(vault.list(), throwsA(isA<BackupLocationException>()));
    });

    test('turns server errors into plain messages', () {
      final vault = VaultBackupLocation(
        baseUrl: base,
        tokens: const _Token('t0k'),
        client: MockClient((_) async => http.Response('', 401)),
      );
      expect(
        vault.list(),
        throwsA(
          isA<BackupLocationException>().having(
            (e) => e.message,
            'message',
            contains('Sign in again'),
          ),
        ),
      );
    });

    test('is off unless a build names the vault', () {
      expect(VaultConfig.uri, isNull);
    });
  });

  group('DriveBackupLocation', () {
    test('creates its folder, then uploads with a resumable session', () async {
      final calls = <String>[];
      List<int>? uploaded;
      final drive = DriveBackupLocation(
        _DriveAuth(),
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          expect(request.headers['Authorization'] ?? 'session', isNotEmpty);
          if (request.method == 'GET') {
            expect(request.url.queryParameters['q'], contains('Pesa Clarity'));
            return http.Response(jsonEncode({'files': <Object>[]}), 200);
          }
          if (request.url.path == '/drive/v3/files') {
            return http.Response(jsonEncode({'id': 'folder1'}), 200);
          }
          if (request.method == 'POST') {
            final meta = jsonDecode(request.body) as Map<String, Object?>;
            expect(meta['parents'], ['folder1']);
            return http.Response(
              '',
              200,
              headers: {'location': 'https://upload.example.test/s1'},
            );
          }
          uploaded = request.bodyBytes;
          return http.Response('{}', 200);
        }),
      );
      await drive.upload(file, 'pesaclarity-2026-10-26-0610.pcbackup');
      expect(calls, [
        'GET /drive/v3/files',
        'POST /drive/v3/files',
        'POST /upload/drive/v3/files',
        'PUT /s1',
      ]);
      expect(uploaded, bytes);
    });

    test('lists only backup files', () async {
      final drive = DriveBackupLocation(
        _DriveAuth(),
        client: MockClient((request) async {
          final q = request.url.queryParameters['q']!;
          if (q.startsWith('name')) {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'folder1'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'f1',
                  'name': 'pesaclarity-2026-10-26-0610.pcbackup',
                  'size': '4000',
                  'createdTime': '2026-10-26T03:10:00Z',
                },
                {
                  'id': 'f2',
                  'name': 'notes.txt',
                  'createdTime': '2026-10-26T03:10:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      final entries = await drive.list();
      expect(entries.map((e) => e.id), ['f1']);
      expect(entries.single.sizeBytes, 4000);
    });

    test('is unavailable without a Google sign-in build', () {
      expect(const UnavailableDriveAuth().isAvailable, isFalse);
    });
  });
}
