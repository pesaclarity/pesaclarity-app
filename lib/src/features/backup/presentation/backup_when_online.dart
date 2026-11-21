import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../application/backup_providers.dart';

/// Finishes backup work that waited for a connection (see
/// [BackupController.catchUp]) once the app is unlocked and set up, and
/// each time it comes back to the front. It shows nothing; offline it
/// tries again next time.
class BackupWhenOnline extends ConsumerStatefulWidget {
  const BackupWhenOnline({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BackupWhenOnline> createState() => _BackupWhenOnlineState();
}

class _BackupWhenOnlineState extends ConsumerState<BackupWhenOnline> {
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
    // Backups read every space; nothing is opened before unlock and setup.
    if (!(ref.read(launchGateProvider).value ?? false)) return;
    _running = true;
    unawaited(
      ref
          .read(backupControllerProvider.notifier)
          .catchUp()
          .then<void>(
            (_) {},
            onError: (Object _) {
              // Best effort: it tries again on the next start or return.
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
