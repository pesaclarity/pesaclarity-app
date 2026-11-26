import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_capability.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_catalogue.dart';

Map<String, Object?> _entry(String tier, {String? url, int ram = 3072}) => {
  'tier': tier,
  'file': '$tier.weights',
  'url': url ?? '${askModelUrlPrefix}slm-models/$tier.weights',
  'size': 72000000,
  'sha256': 'a' * 64,
  'min_ram_mb': ram,
  'parameters': '135M',
  'licence': 'Apache-2.0',
  'credit': 'A made-up model',
};

Future<(Map<String, Object?>, String)> _signed(
  Map<String, Object?> payload, {
  List<int>? seed,
}) async {
  final keys = await Ed25519().newKeyPairFromSeed(seed ?? List.filled(32, 7));
  final bytes = utf8.encode(jsonEncode(payload));
  final signature = await Ed25519().sign(
    AskModelCatalogue.signedBytes(bytes),
    keyPair: keys,
  );
  final public = base64.encode((await keys.extractPublicKey()).bytes);
  return (
    {
      'alg': 'Ed25519',
      'payload': base64.encode(bytes),
      'signature': base64.encode(signature.bytes),
    },
    public,
  );
}

void main() {
  group('catalogue', () {
    test('reads the models a pinned key signed', () async {
      final (envelope, key) = await _signed({
        'format': 1,
        'models': [_entry('full', ram: 4096), _entry('light')],
      });
      final c = await AskModelCatalogue.verify(envelope, publicKeys: [key]);
      expect(c.models.map((m) => m.tier), [
        AskModelTier.light,
        AskModelTier.full,
      ]);
      expect(c[AskModelTier.full]!.minRamMb, 4096);
      expect(c[AskModelTier.light]!.sizeMb, 72);
    });

    test(
      'is empty for another key, a changed payload or a bad envelope',
      () async {
        final (envelope, key) = await _signed({
          'format': 1,
          'models': [_entry('light')],
        });
        final (_, other) = await _signed({}, seed: List.filled(32, 9));
        expect(
          (await AskModelCatalogue.verify(
            envelope,
            publicKeys: [other],
          )).models,
          isEmpty,
        );
        final changed = {
          ...envelope,
          'payload': base64.encode(
            utf8.encode(
              jsonEncode({
                'format': 1,
                'models': [_entry('full')],
              }),
            ),
          ),
        };
        expect(
          (await AskModelCatalogue.verify(changed, publicKeys: [key])).models,
          isEmpty,
        );
        for (final bad in [
          null,
          'x',
          {'alg': 'none'},
          {...envelope, 'alg': 'RS256'},
        ]) {
          expect(
            (await AskModelCatalogue.verify(bad, publicKeys: [key])).models,
            isEmpty,
          );
        }
      },
    );

    test('drops entries off GitHub releases or out of shape', () async {
      final (envelope, key) = await _signed({
        'format': 1,
        'models': [
          _entry('light', url: 'https://example.com/light.weights'),
          {..._entry('full'), 'sha256': 'short'},
        ],
      });
      expect(
        (await AskModelCatalogue.verify(envelope, publicKeys: [key])).models,
        isEmpty,
      );
    });

    test('the bundled catalogue checks out with the pinned key', () async {
      final json = jsonDecode(File(askModelCatalogueAsset).readAsStringSync());
      final c = await AskModelCatalogue.verify(json);
      expect(c.models, isNotEmpty);
      for (final m in c.models) {
        expect(m.url, startsWith(askModelUrlPrefix));
        expect(m.licence, 'Apache-2.0');
      }
    });
  });

  group('capability', () {
    final light = AskModelEntry.tryParse(_entry('light'))!;
    final full = AskModelEntry.tryParse(_entry('full', ram: 4096))!;
    final catalogue = AskModelCatalogue([light, full]);
    const gb = 1024 * 1024 * 1024;
    const room = 2000 * 1000 * 1000;

    test('about 3 GB runs Light, about 4 GB runs both', () {
      List<AskModelTier> tiers(int memory) => [
        for (final m in capableModels(
          catalogue,
          memoryBytes: memory,
          freeBytes: room,
        ))
          m.tier,
      ];
      expect(tiers(2 * gb), isEmpty);
      // A 3 GB phone reports a little less.
      expect(tiers((2.8 * gb).round()), [AskModelTier.light]);
      expect(tiers((3.8 * gb).round()), [
        AskModelTier.light,
        AskModelTier.full,
      ]);
    });

    test('unknown memory, no room or a slow warm-up: no offer', () {
      expect(
        capableModels(catalogue, memoryBytes: null, freeBytes: room),
        isEmpty,
      );
      expect(
        capableModels(catalogue, memoryBytes: 8 * gb, freeBytes: 100000000),
        isEmpty,
      );
      expect(
        capableModels(
          catalogue,
          memoryBytes: 8 * gb,
          freeBytes: room,
          tooSlow: {AskModelTier.light, AskModelTier.full},
        ),
        isEmpty,
      );
    });

    test('warm-up speed', () {
      expect(fastEnough(12), isTrue);
      expect(fastEnough(1.5), isFalse);
    });
  });
}
