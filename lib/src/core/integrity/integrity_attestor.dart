import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/flavor.dart';

/// Why no integrity token could be produced.
enum AttestationUnavailableReason {
  /// The build has no Play Integrity project yet.
  notConfigured,

  /// This build or phone cannot attest, such as the F-Droid build.
  unsupported,

  /// The attestation service returned an error.
  failed,
}

/// The result of asking the platform to vouch for this app and phone.
sealed class Attestation {
  const Attestation();
}

/// A token the server verifies with the attestation service.
final class Attested extends Attestation {
  const Attested(this.token);

  final String token;
}

/// No token. Servers must accept requests without one from foss builds.
final class AttestationUnavailable extends Attestation {
  const AttestationUnavailable(this.reason);

  final AttestationUnavailableReason reason;
}

/// Produces a device and app integrity token bound to a request.
abstract interface class IntegrityAttestor {
  /// Attests a request whose content hashes to [requestHash], so a token
  /// cannot be replayed on a different request.
  Future<Attestation> attest({required String requestHash});
}

/// Play Integrity for the `play` flavour.
///
/// Returns [AttestationUnavailableReason.notConfigured] until the Google Cloud
/// project exists and the Play Integrity dependency is added; both need the
/// Play Console project, which is set up outside this repository.
class PlayIntegrityAttestor implements IntegrityAttestor {
  const PlayIntegrityAttestor({this.cloudProjectNumber = _projectNumber});

  static const _projectNumber = String.fromEnvironment(
    'PESACLARITY_PLAY_CLOUD_PROJECT',
  );

  final String cloudProjectNumber;

  @override
  Future<Attestation> attest({required String requestHash}) async =>
      const AttestationUnavailable(AttestationUnavailableReason.notConfigured);
}

/// The `foss` flavour: F-Droid builds carry no Google services.
class NoIntegrityAttestor implements IntegrityAttestor {
  const NoIntegrityAttestor();

  @override
  Future<Attestation> attest({required String requestHash}) async =>
      const AttestationUnavailable(AttestationUnavailableReason.unsupported);
}

/// The header that carries the integrity token on backup and federated
/// learning requests.
const integrityTokenHeader = 'X-Pesaclarity-Integrity';

/// Adds an integrity token to outgoing requests when one is available.
///
/// Backup upload and federated-learning clients call [headersFor] with the
/// exact body they send and add the returned headers. An unavailable token
/// adds nothing; the server decides what an unattested request may do.
class IntegrityHeaderHook {
  const IntegrityHeaderHook(this._attestor);

  final IntegrityAttestor _attestor;

  Future<Map<String, String>> headersFor(List<int> body) =>
      headersForDigest(Sha256().toSync().hashSync(body).bytes);

  /// Like [headersFor], for a body already hashed with SHA-256, such as a
  /// file streamed from disk.
  Future<Map<String, String>> headersForDigest(List<int> sha256) async {
    final attestation = await _attestor.attest(
      requestHash: requestHashOfDigest(sha256),
    );
    return switch (attestation) {
      Attested(:final token) => {integrityTokenHeader: token},
      AttestationUnavailable() => const {},
    };
  }

  /// The request hash Play Integrity binds a token to: base64url SHA-256.
  static String requestHashOf(List<int> body) =>
      requestHashOfDigest(Sha256().toSync().hashSync(body).bytes);

  static String requestHashOfDigest(List<int> sha256) =>
      base64Url.encode(sha256).replaceAll('=', '');
}

final integrityAttestorProvider = Provider<IntegrityAttestor>(
  (ref) => ref.watch(appFlavorProvider).allowsGoogleServices
      ? const PlayIntegrityAttestor()
      : const NoIntegrityAttestor(),
);

final integrityHeaderHookProvider = Provider<IntegrityHeaderHook>(
  (ref) => IntegrityHeaderHook(ref.watch(integrityAttestorProvider)),
);
