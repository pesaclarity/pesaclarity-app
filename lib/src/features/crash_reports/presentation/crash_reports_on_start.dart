import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_router.dart';
import '../../../routing/app_routes.dart';
import '../../app_status/application/update_check_choice.dart';
import '../application/crash_reports.dart';
import '../data/crash_report_sender.dart';
import '../data/pending_crash_store.dart';
import 'crash_report_sheet.dart';

/// Starts crash capture, and once the app is unlocked and onboarded deals
/// with the reports waiting from the last run (ADR 0024). It shows nothing:
/// with Ask each time, reports wait for the sheet that asks. Reports the
/// person chose to send while offline go when the app returns online.
class CrashReportsOnStart extends ConsumerStatefulWidget {
  const CrashReportsOnStart({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CrashReportsOnStart> createState() =>
      _CrashReportsOnStartState();
}

class _CrashReportsOnStartState extends ConsumerState<CrashReportsOnStart> {
  bool _handled = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(_install());
    // Reports the person chose to send while offline go once online.
    _lifecycle = AppLifecycleListener(onResume: _sendChosen);
    ref.listenManual(launchGateProvider, (_, gate) {
      if ((gate.value ?? false) && !_handled) {
        _handled = true;
        unawaited(
          _handle().then<void>(
            (_) {},
            onError: (Object _) {
              // Best effort: the reports wait for the next start.
            },
          ),
        );
      }
    }, fireImmediately: true);
  }

  /// Sends or deletes the waiting reports as chosen; with Ask each time,
  /// once policy 2.4 is agreed, asks with the sheet.
  Future<void> _handle() async {
    final outcome = await ref.read(pendingCrashReportsProvider.future);
    if (outcome != PendingOutcome.waitingForAnswer || !mounted) return;
    if (!await ref.read(agreedToReportingPolicyProvider.future)) return;
    final reports = await ref.read(pendingCrashStoreProvider).read();
    if (reports.isEmpty || !mounted) return;
    final router = ref.read(appRouterProvider);
    await _settledOn(router);
    if (!mounted) return;
    final navigator = router.routerDelegate.navigatorKey.currentContext;
    if (navigator == null || !navigator.mounted) return;
    await showCrashReportSheet(navigator, reports);
  }

  void _sendChosen() {
    if (!_handled || !mounted) return;
    unawaited(
      sendChosenCrashReports(
        ref.read(pendingCrashStoreProvider),
        ref.read(crashReportSenderProvider),
      ).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Waits until [router] has left the launch screen (and the space
  /// question) for the screen the person stays on. A sheet shown over the
  /// launch screen goes with it when the app moves on to Home.
  Future<void> _settledOn(GoRouter router) async {
    bool passing() => const {
      AppRoutes.launch,
      AppRoutes.chooseSpace,
    }.contains(router.routerDelegate.currentConfiguration.uri.path);
    if (passing()) {
      final left = Completer<void>();
      void check() {
        if (!passing() && !left.isCompleted) left.complete();
      }

      router.routerDelegate.addListener(check);
      try {
        await left.future;
      } finally {
        router.routerDelegate.removeListener(check);
      }
    }
    // The new screen is built before the sheet goes over it.
    await WidgetsBinding.instance.endOfFrame;
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
