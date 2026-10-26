import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/onboarding_repository.dart';

/// Whether the person has finished onboarding, loaded from the database.
class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(onboardingRepositoryProvider).isComplete();

  /// Finishes onboarding after the person picks their accounts.
  Future<void> complete() async {
    // TODO(#2): ask for SMS permission and start the 90-day scan of
    // senderWatchListProvider before leaving onboarding.
    await ref.read(onboardingRepositoryProvider).markComplete();
    state = const AsyncData(true);
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);
