import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/privacy/privacy_policy.dart';
import '../../app_status/application/update_links.dart';
import '../../privacy/application/consent_controller.dart';
import '../../privacy/data/policy_source.dart';
import '../data/count_token_store.dart';
import '../domain/count_token.dart';

/// The policy that describes the monthly count. No token is sent before the
/// person has seen it.
final reportingPolicyVersion = PolicyVersion.parse('2.4');

/// "Count this phone in monthly totals": on for the Play, iPhone and website
/// builds, off in the F-Droid build until the person turns it on (ADR 0024,
/// owner's decision 1).
bool countingDefaultFor(UpdateChannel channel) => channel != UpdateChannel.foss;

/// The person's counting choice, kept with the other privacy settings.
class CountingChoice {
  const CountingChoice({required this.value, required this.changedAt});

  static CountingChoice? fromJson(Map<String, Object?>? json) {
    final value = json?['value'];
    final at = json?['changedAt'];
    final time = at is String ? DateTime.tryParse(at)?.toUtc() : null;
    if (value is! bool || time == null) return null;
    return CountingChoice(value: value, changedAt: time);
  }

  final bool value;
  final DateTime changedAt;

  Map<String, Object?> toJson() => {
    'value': value,
    'changedAt': changedAt.toIso8601String(),
  };
}

/// Whether this phone is counted: the person's choice, or the build's
/// default when they have not made one.
class CountingController extends AsyncNotifier<bool> {
  static const settingsKey = 'privacy.counting';

  @override
  Future<bool> build() async {
    final saved = CountingChoice.fromJson(
      await ref.read(mainSettingsRepositoryProvider).readJson(settingsKey),
    );
    return saved?.value ?? countingDefaultFor(ref.watch(updateChannelProvider));
  }

  /// Switches counting on or off. Off deletes the token at once; the update
  /// check carries on without it.
  Future<void> setEnabled(bool value) async {
    final choice = CountingChoice(
      value: value,
      changedAt: ref.read(clockProvider)().toUtc(),
    );
    await ref
        .read(mainSettingsRepositoryProvider)
        .writeJson(settingsKey, choice.toJson());
    if (!value) await ref.read(countTokenStoreProvider).delete();
    state = AsyncData(value);
  }
}

final countingControllerProvider =
    AsyncNotifierProvider<CountingController, bool>(CountingController.new);

/// Gives the update check its counting token, or null when it must go
/// without one.
class CountTokenIssuer {
  CountTokenIssuer(this._ref, {this.random});

  final Ref _ref;

  /// The source of randomness; [Random.secure] unless a test sets one.
  final Random? random;

  /// This month's token, made on first use in the month and replaced on the
  /// first check-in of the next. Null unless counting is on and the person
  /// has agreed to a policy that describes it (2.4 or later) with nothing
  /// newer waiting for review. When counting is off any token is deleted.
  Future<String?> tokenForCheckIn() async {
    final store = _ref.read(countTokenStoreProvider);
    final enabled = await _ref.read(countingControllerProvider.future);
    if (!enabled) {
      await store.delete();
      return null;
    }
    final policy = await _ref.read(privacyPolicyProvider.future);
    final consent = await _ref.read(consentControllerProvider.future);
    final accepted = consent.acceptedVersion;
    if (accepted == null ||
        reportingPolicyVersion.isNewerThan(accepted) ||
        consent.needsReview(policy)) {
      return null;
    }
    final now = _ref.read(clockProvider)();
    final saved = await store.read();
    if (saved != null && saved.isFor(now)) return saved.value;
    final token = CountToken.make(now, random: random);
    await store.write(token);
    return token.value;
  }
}

final countTokenIssuerProvider = Provider<CountTokenIssuer>(
  CountTokenIssuer.new,
);
