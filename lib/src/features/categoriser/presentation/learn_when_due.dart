import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../application/categoriser_providers.dart';

/// Checks whether on-phone learning is due once the app is unlocked and set
/// up, and each time it comes back to the front. Nothing is read before
/// then: opening the database while it is locked would fail for the whole
/// session. Learning itself runs only with consent, while charging, and at
/// most as often as the model allows.
class LearnWhenDue extends ConsumerStatefulWidget {
  const LearnWhenDue({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<LearnWhenDue> createState() => _LearnWhenDueState();
}

class _LearnWhenDueState extends ConsumerState<LearnWhenDue> {
  late final AppLifecycleListener _lifecycle;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
    ref.listenManual(launchGateProvider, (_, gate) {
      if (gate.value ?? false) _check();
    }, fireImmediately: true);
  }

  void _check() {
    if (_running || !mounted) return;
    // Unlocked and onboarded; anything else and the database stays shut.
    if (!(ref.read(launchGateProvider).value ?? false)) return;
    _running = true;
    unawaited(
      runLearningIfDue(ref)
          .then<void>(
            (_) {},
            onError: (Object _) {
              // Learning is best effort; suggestions keep working without it.
            },
          )
          .whenComplete(() => _running = false),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
