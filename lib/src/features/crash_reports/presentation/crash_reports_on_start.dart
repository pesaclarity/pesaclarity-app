import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../application/crash_reports.dart';
import '../data/pending_crash_store.dart';

/// Starts crash capture, and once the app is unlocked and onboarded deals
/// with the reports waiting from the last run (ADR 0024). It shows nothing:
/// with Ask each time, reports wait for the sheet that asks.
class CrashReportsOnStart extends ConsumerStatefulWidget {
  const CrashReportsOnStart({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CrashReportsOnStart> createState() =>
      _CrashReportsOnStartState();
}

class _CrashReportsOnStartState extends ConsumerState<CrashReportsOnStart> {
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_install());
    ref.listenManual(launchGateProvider, (_, gate) {
      if ((gate.value ?? false) && !_handled) {
        _handled = true;
        unawaited(
          ref
              .read(pendingCrashReportsProvider.future)
              .then<void>(
                (_) {},
                onError: (Object _) {
                  // Best effort: the reports wait for the next start.
                },
              ),
        );
      }
    }, fireImmediately: true);
  }

  Future<void> _install() async {
    try {
      final context = await ref.read(crashContextProvider.future);
      if (context == null || !mounted) return;
      CrashCapture(
        store: ref.read(pendingCrashStoreProvider),
        context: context,
      ).install();
    } on Object {
      // No capture on a phone or build the report cannot name.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
