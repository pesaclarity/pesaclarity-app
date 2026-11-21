import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

/// Renews a signed-in session in the background when the app opens and
/// each time it comes back to the front (at most every few hours, see
/// [AuthController.revalidate]). It shows nothing and holds nothing up:
/// offline it simply tries again next time.
class KeepSessionFresh extends ConsumerStatefulWidget {
  const KeepSessionFresh({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<KeepSessionFresh> createState() => _KeepSessionFreshState();
}

class _KeepSessionFreshState extends ConsumerState<KeepSessionFresh> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _revalidate);
    _revalidate();
  }

  void _revalidate() {
    if (!mounted) return;
    unawaited(ref.read(authControllerProvider.notifier).revalidate());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
