import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the person has finished onboarding.
///
/// TODO(onboarding): persist completion in the encrypted database so it
/// survives restarts; today it resets on every launch.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() => false;

  void complete() => state = true;
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
