import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../application/group_sync_controller.dart';

/// Syncs the open shared space once the app is unlocked and set up, and
/// each time it comes back to the front (decision 0033; no live updates
/// yet). Pull-to-refresh on the space's screens syncs too. Problems are
/// kept for Share this space. With the build's sync switch off it does
/// nothing.
class GroupSyncWhenOpen extends ConsumerStatefulWidget {
  const GroupSyncWhenOpen({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<GroupSyncWhenOpen> createState() => _GroupSyncWhenOpenState();
}

class _GroupSyncWhenOpenState extends ConsumerState<GroupSyncWhenOpen> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    if (!ref.read(groupSyncFlagProvider)) return;
    _lifecycle = AppLifecycleListener(onResume: _sync);
    ref.listenManual(launchGateProvider, (_, gate) {
      if (gate.value ?? false) _sync();
    }, fireImmediately: true);
  }

  void _sync() {
    if (!mounted) return;
    if (!(ref.read(launchGateProvider).value ?? false)) return;
    unawaited(
      ref
          .read(groupSyncProvider.notifier)
          .sync()
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
