import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/onboarding_repository.dart';

/// Whether the person has finished onboarding, loaded from the database.
class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(onboardingRepositoryProvider).isComplete();

  /// Finishes onboarding, after the first scan or once the person chooses
  /// to go on without one.
  Future<void> complete() async {
    await ref.read(onboardingRepositoryProvider).markComplete();
    state = const AsyncData(true);
  }
}

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);
