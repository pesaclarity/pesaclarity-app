import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../counting/application/counting.dart';
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import 'update_links.dart';

/// Whether the F-Droid build may make its daily update check (ADR 0024,
/// owner's decision 2): null until the person has answered "Check for
/// updates?", then their answer. Other builds never ask.
class UpdateCheckChoiceController extends AsyncNotifier<bool?> {
  static const settingsKey = 'privacy.updateCheck';

  @override
  Future<bool?> build() async {
    final saved = await ref
        .read(mainSettingsRepositoryProvider)
        .readJson(settingsKey);
    final value = saved?['value'];
    return value is bool ? value : null;
  }

  /// Saves the answer. "Check daily" is true, "Not now" false.
  Future<void> answer(bool value) async {
    await ref.read(mainSettingsRepositoryProvider).writeJson(settingsKey, {
      'value': value,
      'changedAt': ref.read(clockProvider)().toUtc().toIso8601String(),
    });
    state = AsyncData(value);
  }
}

final updateCheckChoiceProvider =
    AsyncNotifierProvider<UpdateCheckChoiceController, bool?>(
      UpdateCheckChoiceController.new,
    );

/// Whether the person has agreed to policy 2.4 or later, which describes
/// asking first, with nothing newer waiting for review.
final agreedToReportingPolicyProvider = FutureProvider<bool>((ref) async {
  final policy = await ref.watch(privacyPolicyProvider.future);
  final consent = await ref.watch(consentControllerProvider.future);
  final accepted = consent.acceptedVersion;
  return accepted != null &&
      !reportingPolicyVersion.isNewerThan(accepted) &&
      !consent.needsReview(policy);
});

/// Whether the daily update check may run. Builds other than F-Droid always
/// may. The F-Droid build may only after "Check daily", once policy 2.4 is
/// agreed; before that it keeps checking as it always has, without a
/// counting token, until the person has seen the policy that says it asks.
final updateCheckAllowedProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(updateChannelProvider) != UpdateChannel.foss) return true;
  if (!await ref.watch(agreedToReportingPolicyProvider.future)) return true;
  final answer = await ref.watch(updateCheckChoiceProvider.future);
  return answer ?? false;
});

/// Whether to show "Check for updates?" now: the F-Droid build, policy 2.4
/// agreed, and no answer yet.
final updateCheckQuestionProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(updateChannelProvider) != UpdateChannel.foss) return false;
  if (!await ref.watch(agreedToReportingPolicyProvider.future)) return false;
  final answer = await ref.watch(updateCheckChoiceProvider.future);
  return answer == null;
});
