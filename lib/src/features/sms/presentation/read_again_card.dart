import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/read_again.dart';
import '../application/sms_capture_providers.dart';
import '../application/sms_ingestor.dart';
import '../data/sms_source.dart';

/// `2,960`.
String countLabel(int n) {
  final digits = '$n';
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Activity narrowed to the days, and the account when there is one, of
/// the transactions [changes] added or updated.
ActivityFilter changedFilter(List<ReadChange> changes) {
  final days = [for (final c in changes) CalendarDate.local(c.at)]..sort();
  final accounts = {for (final c in changes) c.accountId};
  return ActivityFilter(
    accountId: accounts.length == 1 ? accounts.single : null,
    from: days.firstOrNull,
    to: days.lastOrNull,
  );
}

/// "Read messages again", under "Read messages from": reads every ticked
/// account's messages again with the readers this app has, then says what
/// changed. The read goes on when the person leaves the screen.
class ReadAgainCard extends ConsumerWidget {
  const ReadAgainCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // iPhone has no inbox to read again: messages come one at a time.
    if (ref.watch(smsSourceProvider) is ShortcutSmsSource ||
        ref.watch(selectedInstitutionsProvider).isEmpty) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(readAgainControllerProvider);
    final last = ref.watch(lastReadProvider).value;
    void readAgain() =>
        ref.read(readAgainControllerProvider.notifier).readAgain();

    final button = PillButton(
      key: const Key('read-again'),
      label: 'Read again',
      onPressed: readAgain,
    );
    return Card(
      key: const Key('read-again-card'),
      child: switch (state.stage) {
        ReadAgainStage.reading => _Reading(state),
        ReadAgainStage.finished => _Finished(state, button: button),
        ReadAgainStage.failed => _Body(
          title: 'Read messages again',
          body:
              'Your messages could not be read again. Nothing was changed. '
              'Try again.',
          button: button,
        ),
        ReadAgainStage.idle => _Body(
          title: 'Read messages again',
          body:
              'Reads your messages again with the latest readers, to catch '
              'any that were missed. Your names and categories stay.',
          button: button,
          footer: last?.at == null
              ? null
              : 'Last read ${shortDate(CalendarDate.local(last!.at!))}, '
                    'with readers ${last.readers.engine}',
        ),
      },
    );
  }
}

/// The card's text and button, in the padding a list tile has.
class _Body extends StatelessWidget {
  const _Body({
    required this.title,
    required this.body,
    required this.button,
    this.footer,
  });

  final String title;
  final String body;
  final Widget button;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.all(Layout.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text(body, style: muted),
          const SizedBox(height: 12),
          button,
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(footer!, key: const Key('read-again-last'), style: muted),
          ],
        ],
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.state);

  final ReadAgainState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final total = state.total;
    final progress = total == 0
        ? 'Looking for your messages'
        : '${countLabel(state.done)} of ${countLabel(total)} messages';
    return Padding(
      padding: const EdgeInsets.all(Layout.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reading your messages again', style: theme.textTheme.bodyLarge),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
            child: LinearProgressIndicator(
              value: total == 0 ? null : state.done / total,
              minHeight: 6,
              color: theme.colorScheme.onSurface,
              backgroundColor: colors.border,
              semanticsLabel: 'Reading progress',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$progress · You can leave this screen',
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Finished extends ConsumerWidget {
  const _Finished(this.state, {required this.button});

  final ReadAgainState state;
  final Widget button;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = state.summary;
    final changed = summary.changes.isNotEmpty;
    final now = ref.watch(clockProvider)();
    final at = state.at ?? now;
    final when = now.difference(at) < const Duration(minutes: 5)
        ? 'just now'
        : CalendarDate.local(at) == CalendarDate.local(now)
        ? 'today'
        : 'on ${shortDate(CalendarDate.local(at))}';
    final title = summary.added + summary.updated == 0
        ? 'Nothing new'
        : '${countLabel(summary.added)} new, '
              '${countLabel(summary.updated)} updated';
    final messages = state.total == 1
        ? '1 message'
        : '${countLabel(state.total)} messages';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: const Key('read-again-result'),
          contentPadding: const EdgeInsetsDirectional.fromSTEB(
            Layout.cardPadding,
            4,
            12,
            0,
          ),
          title: Text(title),
          subtitle: Text('Read again $when · $messages'),
          trailing: changed
              ? Icon(
                  Icons.chevron_right,
                  color: PesaColors.of(context).textMuted,
                )
              : null,
          onTap: changed
              ? () => context.go(
                  AppRoutes.activityWith(changedFilter(summary.changes)),
                )
              : null,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Layout.cardPadding,
            0,
            Layout.cardPadding,
            Layout.cardPadding,
          ),
          child: button,
        ),
      ],
    );
  }
}
