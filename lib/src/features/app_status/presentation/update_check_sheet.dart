import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routing/app_router.dart';
import '../../../shared/accessibility.dart';
import '../../../theme/layout.dart';
import '../../counting/application/counting.dart';
import '../application/update_check_choice.dart';

/// "Check for updates?": the F-Droid build asks before its first daily
/// update check (ADR 0024, owner's decision 2), as in the approved mockup.
/// "Check daily" turns the check on, and counting too when its box is
/// ticked; "Not now" sends nothing.
class UpdateCheckSheet extends ConsumerStatefulWidget {
  const UpdateCheckSheet({super.key});

  static const title = 'Check for updates?';
  static const body =
      'Once a day the app can ask our server whether a newer version '
      'or a notice is waiting, such as a fix for a bank that changed '
      'its messages. It sends only the app version, the build and the '
      'platform. Nothing is sent until you say yes.';
  static const countTitle = 'Count this phone in monthly totals';
  static const countSubtitle =
      'A random number, new each month, sent with the update check. '
      'Never your data';
  static const yes = 'Check daily';
  static const no = 'Not now';
  static const footer = 'Change it any time in Privacy';

  @override
  ConsumerState<UpdateCheckSheet> createState() => _UpdateCheckSheetState();
}

class _UpdateCheckSheetState extends ConsumerState<UpdateCheckSheet> {
  bool _count = false;
  bool _busy = false;

  Future<void> _answer(bool yes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (yes && _count) {
        await ref.read(countingControllerProvider.notifier).setEnabled(true);
      }
      await ref.read(updateCheckChoiceProvider.notifier).answer(yes);
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                UpdateCheckSheet.title,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(UpdateCheckSheet.body, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Layout.titleGap),
            CheckboxListTile(
              value: _count,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _count = value ?? false),
              title: const Text(UpdateCheckSheet.countTitle),
              subtitle: const Text(UpdateCheckSheet.countSubtitle),
            ),
            const SizedBox(height: Layout.titleGap),
            FilledButton(
              onPressed: _busy ? null : () => _answer(true),
              child: const Text(UpdateCheckSheet.yes),
            ),
            const SizedBox(height: Layout.cardGap),
            OutlinedButton(
              onPressed: _busy ? null : () => _answer(false),
              child: const Text(UpdateCheckSheet.no),
            ),
            const SizedBox(height: 8),
            Text(
              UpdateCheckSheet.footer,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [UpdateCheckSheet]. Closing it without an answer asks again on
/// the next start.
Future<void> showUpdateCheckSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      sheetAnimationStyle: reduceMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => const UpdateCheckSheet(),
    );

/// Shows "Check for updates?" once the app is unlocked and onboarded, in
/// the F-Droid build only, after policy 2.4 is agreed and until the person
/// answers.
class AskBeforeUpdateCheck extends ConsumerStatefulWidget {
  const AskBeforeUpdateCheck({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AskBeforeUpdateCheck> createState() =>
      _AskBeforeUpdateCheckState();
}

class _AskBeforeUpdateCheckState extends ConsumerState<AskBeforeUpdateCheck> {
  bool _shown = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    // The question reads the saved consent, so only once the database is
    // open: after unlock and onboarding.
    ref.listenManual(launchGateProvider, (_, gate) {
      if (!(gate.value ?? false) || _listening) return;
      _listening = true;
      ref.listenManual(
        updateCheckQuestionProvider,
        (_, _) => _maybeAsk(),
        fireImmediately: true,
      );
    }, fireImmediately: true);
  }

  void _maybeAsk() {
    if (_shown || !mounted) return;
    if (!(ref.read(updateCheckQuestionProvider).value ?? false)) return;
    final navigator = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (navigator == null) return;
    _shown = true;
    unawaited(showUpdateCheckSheet(navigator));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
