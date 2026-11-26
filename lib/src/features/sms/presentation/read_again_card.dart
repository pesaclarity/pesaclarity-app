import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/application/my_accounts_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/read_again.dart';
import '../application/sms_capture_providers.dart';
import '../application/sms_ingestor.dart';
import '../data/sms_source.dart';
import 'read_again_home_card.dart' show namesList;

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
///
/// On Android it always shows, and says why when it cannot read: the
/// accounts are still being checked, could not be read, or none is on in
/// this space.
class ReadAgainCard extends ConsumerWidget {
  const ReadAgainCard({super.key});

  static const _title = 'Read messages again';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // iPhone has no inbox to read again: messages come one at a time.
    if (ref.watch(smsSourceProvider) is ShortcutSmsSource) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(readAgainControllerProvider);
    final ids = ref.watch(selectedInstitutionIdsProvider);
    final selected = ref.watch(selectedInstitutionsProvider);
    final last = ref.watch(lastReadProvider).value;
    final controller = ref.read(readAgainControllerProvider.notifier);

    final button = PillButton(
      key: const Key('read-again'),
      label: 'Read again',
      onPressed: controller.readAgain,
    );
    final Widget child;
    if (state.reading) {
      child = _Reading(state);
    } else if (ids.isLoading) {
      child = const _Body(
        title: _title,
        body: 'Checking your accounts…',
        button: PillButton(
          key: Key('read-again'),
          label: 'Read again',
          onPressed: null,
        ),
      );
    } else if (ids.hasError) {
      child = _Body(
        title: _title,
        body: 'Your accounts could not be read.',
        button: PillButton(
          key: const Key('read-again-retry'),
          label: 'Try again',
          onPressed: () => ref.invalidate(selectedInstitutionIdsProvider),
        ),
      );
    } else if (selected.isEmpty) {
      child = const _NoAccounts();
    } else {
      child = switch (state.stage) {
        ReadAgainStage.reading => _Reading(state),
        ReadAgainStage.finished => _Finished(state, button: button),
        ReadAgainStage.failed => _Body(
          title: _title,
          body:
              'Your messages could not be read again. Nothing was changed. '
              'Try again.',
          button: button,
        ),
        // The accounts were switched off as the read began.
        ReadAgainStage.noAccounts => _Body(
          title: _title,
          body: 'No account was on, so nothing was read. Try again.',
          button: button,
        ),
        ReadAgainStage.noAccess => _Body(
          title: _title,
          body:
              'Pesa Clarity is not allowed to read your messages, so nothing '
              'was read. Allow messages in Settings, then read again.',
          button: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillButton(
                key: const Key('read-again-settings'),
                label: 'Open settings',
                onPressed: () => ref.read(smsSourceProvider).openSettings(),
              ),
              button,
            ],
          ),
        ),
        ReadAgainStage.idle => _Body(
          title: _title,
          body:
              'Reads your messages again with the latest readers, to catch '
              'any that were missed. Your names and categories stay.',
          button: button,
          footer: last?.at == null
              ? null
              : 'Last read ${shortDate(CalendarDate.local(last!.at!))}, '
                    'with readers ${last.readers.engine}',
        ),
      };
    }
    return Card(key: const Key('read-again-card'), child: child);
  }
}

/// No account is on in this space: says why, and what to do. An account
/// another space reads is named with that space (each account is read in
/// one space); in a business whose account Personal reads, it leads to
/// Business or personal, where it can be shared.
class _NoAccounts extends ConsumerWidget {
  const _NoAccounts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elsewhere = ref.watch(readElsewhereProvider).value;
    final here = ref.watch(activeSpaceProvider);
    const switchOn = 'Switch on an account above to read its messages.';
    if (elsewhere == null) {
      return const _Body(
        key: Key('read-again-none'),
        title: ReadAgainCard._title,
        body: switchOn,
      );
    }
    final reader = elsewhere.space;
    final names = elsewhere.institutions.map((i) => i.name).toList();
    final one = names.length == 1;
    final share =
        reader.id == personalSpaceId && here.kind == SpaceKind.business;
    final read =
        '${namesList(names)} ${one ? 'is' : 'are'} read in '
        '${reader.name}.';
    final its = one ? 'its' : 'their';
    return _Body(
      key: const Key('read-again-none'),
      title: ReadAgainCard._title,
      body: share
          ? '$read Open ${reader.name} to read $its messages again, or '
                'choose in Business or personal.'
          : '$read Open ${reader.name} to read $its messages again, or '
                '${switchOn[0].toLowerCase()}${switchOn.substring(1)}',
      button: share
          ? PillButton(
              key: const Key('read-again-choose'),
              label: 'Business or personal',
              onPressed: () => context.push(AppRoutes.businessOrPersonal),
            )
          : null,
    );
  }
}

/// The card's text and button, in the padding a list tile has.
class _Body extends StatelessWidget {
  const _Body({
    required this.title,
    required this.body,
    this.button,
    this.footer,
    super.key,
  });

  final String title;
  final String body;
  final Widget? button;
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
          if (button != null) ...[const SizedBox(height: 12), button!],
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
