import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/integrity/integrity_attestor.dart';

class FakeAttestor implements IntegrityAttestor {
  FakeAttestor(this.result);

  final Attestation result;
  final hashes = <String>[];

  @override
  Future<Attestation> attest({required String requestHash}) async {
    hashes.add(requestHash);
    return result;
  }
}

void main() {
  IntegrityAttestor attestorFor(AppFlavor flavor) {
    final container = ProviderContainer(
      overrides: [appFlavorProvider.overrideWithValue(flavor)],
    );
    addTearDown(container.dispose);
    return container.read(integrityAttestorProvider);
  }

  test(
    'play uses the Play stub, unavailable until the project exists',
    () async {
      final attestor = attestorFor(AppFlavor.play);
      expect(attestor, isA<PlayIntegrityAttestor>());
      final result = await attestor.attest(requestHash: 'x');
      expect(
        (result as AttestationUnavailable).reason,
        AttestationUnavailableReason.notConfigured,
      );
    },
  );

  test('foss never attests', () async {
    final attestor = attestorFor(AppFlavor.foss);
    expect(attestor, isA<NoIntegrityAttestor>());
    final result = await attestor.attest(requestHash: 'x');
    expect(
      (result as AttestationUnavailable).reason,
      AttestationUnavailableReason.unsupported,
    );
  });

  test('the hook adds the token, bound to the body hash', () async {
    final attestor = FakeAttestor(const Attested('token-123'));
    final headers = await IntegrityHeaderHook(attestor).headersFor([1, 2, 3]);
    expect(headers, {integrityTokenHeader: 'token-123'});
    // SHA-256 of [1, 2, 3], base64url without padding.
    expect(attestor.hashes, ['A5BYxvLAy0ksUzsKTRTvd8wPeKvMztUofYShogEc-4E']);
  });

  test('the hook adds nothing when no token is available', () async {
    final hook = IntegrityHeaderHook(
      FakeAttestor(
        const AttestationUnavailable(AttestationUnavailableReason.failed),
      ),
    );
    expect(await hook.headersFor([1]), isEmpty);
  });
}
