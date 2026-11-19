import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/accessibility.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/crash_reports.dart';
import '../data/crash_report_sender.dart';
import '../data/pending_crash_store.dart';
import '../domain/crash_report.dart';

/// "Pesa Clarity closed last time": asks on the next start whether to send
/// the waiting reports, and shows exactly what would be sent (ADR 0024).
/// "Do the same next time" turns the answer into Always send or Never send.
class CrashReportSheet extends ConsumerStatefulWidget {
  const CrashReportSheet({required this.reports, super.key});

  final List<CrashReport> reports;

  static const title = 'Pesa Clarity closed last time';
  static const body =
      'Something went wrong in the app. A crash report tells us where, so '
      'we can fix it. It holds no amounts, messages, names or numbers.';
  static const seeTitle = 'See what will be sent';
  static const seeSubtitle = 'Exactly this, and nothing else';
  static const stackNote =
      "The stack is where in the app's own code it stopped, as numbers. We "
      'turn them into names on our server. Kept 90 days, with no account, '
      'phone or install id.';
  static const sameTitle = 'Do the same next time';
  static const sameSubtitle = 'Change it any time in Privacy';
  static const send = 'Send report';
  static const dontSend = "Don't send";

  @override
  ConsumerState<CrashReportSheet> createState() => _CrashReportSheetState();
}

class _CrashReportSheetState extends ConsumerState<CrashReportSheet> {
  bool _open = false;
  bool _same = false;
  bool _busy = false;

  Future<void> _answer({required bool send}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = ref.read(pendingCrashStoreProvider);
      final sender = ref.read(crashReportSenderProvider);
      if (send && sender != null) {
        await sendCrashReports(store, sender, widget.reports);
      } else if (!send) {
        await store.clear();
      }
      if (_same) {
        await ref
            .read(crashReportChoiceProvider.notifier)
            .choose(send ? CrashReportChoice.always : CrashReportChoice.never);
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = colors.textMuted;
    final preview = widget.reports.map((r) => r.preview).join('\n\n');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Layout.gutter,
          8,
          Layout.gutter,
          Layout.screenBottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                CrashReportSheet.title,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              CrashReportSheet.body,
              style: theme.textTheme.bodyMedium!.copyWith(color: muted),
            ),
            const SizedBox(height: Layout.titleGap),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: const Text(CrashReportSheet.seeTitle),
                    subtitle: Text(
                      CrashReportSheet.seeSubtitle,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    trailing: Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: _open ? theme.colorScheme.primary : null,
                    ),
                    onTap: () => setState(() => _open = !_open),
                  ),
                  if (_open)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Layout.cardPadding,
                        0,
                        Layout.cardPadding,
                        Layout.cardPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.selected,
                              borderRadius: BorderRadius.circular(
                                Layout.panelRadius,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Layout.cardPadding),
                              child: SelectableText(
                                preview,
                                style: theme.textTheme.bodySmall!.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const [
                                    'Courier',
                                    BrandTokens.bodyFont,
                                  ],
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: Layout.cardGap),
                          Text(
                            CrashReportSheet.stackNote,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Layout.titleGap),
            CheckboxListTile(
              value: _same,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _same = value ?? false),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text(CrashReportSheet.sameTitle),
              subtitle: const Text(CrashReportSheet.sameSubtitle),
            ),
            const SizedBox(height: Layout.titleGap),
            FilledButton(
              onPressed: _busy ? null : () => _answer(send: true),
              child: const Text(CrashReportSheet.send),
            ),
            const SizedBox(height: Layout.cardGap),
            OutlinedButton(
              onPressed: _busy ? null : () => _answer(send: false),
              child: const Text(CrashReportSheet.dontSend),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showCrashReportSheet(
  BuildContext context,
  List<CrashReport> reports,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  sheetAnimationStyle: reduceMotion(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => CrashReportSheet(reports: reports),
);
