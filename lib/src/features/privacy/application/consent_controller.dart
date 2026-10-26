import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/privacy/consent.dart';
import '../../../domain/privacy/privacy_policy.dart';
import '../data/policy_source.dart';

/// The person's privacy choices, saved on the phone with the policy version
/// and time of each.
class ConsentController extends AsyncNotifier<ConsentRecord> {
  static const recordKey = 'privacy.consent';

  @override
  Future<ConsentRecord> build() async {
    final json = await ref
        .read(appSettingsRepositoryProvider)
        .readJson(recordKey);
    return json == null ? const ConsentRecord() : ConsentRecord.fromJson(json);
  }

  /// Sets one switch under the bundled policy's version.
  Future<void> setChoice(ConsentKind kind, bool value) async {
    final policy = await ref.read(privacyPolicyProvider.future);
    final current = state.value ?? await future;
    await _save(
      current.withChoice(
        kind,
        value,
        at: ref.read(clockProvider)(),
        policyVersion: policy.version,
      ),
    );
  }

  /// Agrees to [policy] with [values] for the switches, such as after
  /// reviewing what changed or on first run.
  Future<void> accept(
    PrivacyPolicy policy, {
    Map<ConsentKind, bool> values = const {},
  }) async {
    final current = state.value ?? await future;
    await _save(
      current.accept(
        policy.version,
        at: ref.read(clockProvider)(),
        values: values,
      ),
    );
  }

  Future<void> _save(ConsentRecord record) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(recordKey, record.toJson());
    state = AsyncData(record);
  }
}

final consentControllerProvider =
    AsyncNotifierProvider<ConsentController, ConsentRecord>(
      ConsentController.new,
    );

/// The policy changes to show when the bundled policy is newer than the one
/// agreed to, newest first; null when there is nothing to review.
final policyReviewProvider = FutureProvider<List<PolicyChange>?>((ref) async {
  final policy = await ref.watch(privacyPolicyProvider.future);
  final record = await ref.watch(consentControllerProvider.future);
  if (!record.needsReview(policy)) return null;
  return policy.changesSince(record.acceptedVersion!);
});
