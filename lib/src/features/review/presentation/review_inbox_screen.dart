import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../application/review_draft.dart';
import '../application/review_providers.dart';

/// Messages from the person's accounts that no parser rule read, each with
/// what the reader suggests. Opened from the Home card.
class ReviewInboxScreen extends ConsumerWidget {
  const ReviewInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final pending = ref.watch(pendingReviewProvider);
    final items = pending.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages to check'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: switch (pending) {
        AsyncValue(hasValue: false, hasError: true) => ErrorView(
          'Messages to check could not load.',
          onRetry: () => ref.invalidate(pendingReviewProvider),
        ),
        AsyncValue(hasValue: false) => const LoadingView(),
        _ => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'New wording from your accounts. Check each one once and Pesa '
              'Clarity reads it next time.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const EmptyNote(
                'All checked. Messages with new wording show here.',
              )
            else
              GroupedSection(
                footer:
                    'The message text stays encrypted on this phone and is '
                    'deleted once you check it.',
                children: [for (final item in items) _ItemTile(item)],
              ),
          ],
        ),
      },
    );
  }
}

String _initials(String name) {
  final words = name.split(' ').where((w) => w.isNotEmpty).toList();
  return words.take(2).map((w) => w[0].toUpperCase()).join();
}

/// "Money out · 1,250 to Example Grocers", or null when nothing was read.
String? suggestionLabel(ReviewDraft draft, {bool hidden = false}) {
  if (draft.kind == MessageKind.notTransaction) return 'A notice';
  final amount = draft.amountMinor;
  if (amount == null) return null;
  final out = draft.kind == MessageKind.moneyOut;
  final money = moneyOrHidden(hidden: hidden, amount, withCurrency: false);
  final party = draft.counterparty;
  return '${out ? 'Money out' : 'Money in'} · $money'
      '${party == null ? '' : '${out ? ' to' : ' from'} $party'}';
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile(this.item);

  final ReviewItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final institution = ref
        .watch(institutionCatalogueProvider)
        .where((i) => i.id == item.institutionId)
        .firstOrNull;
    final name = institution?.name ?? item.sender;
    final reading = ref.watch(reviewReadingProvider(item.id));
    final suggestion = reading == null
        ? null
        : suggestionLabel(
            ReviewDraft.fromReading(reading),
            hidden: AmountsHidden.of(context),
          );
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final day = CalendarDate.local(item.receivedAt);
    final when = day == today
        ? 'Today ${formatTime(item.receivedAt)}'
        : dayHeading(day, today: today);
    final body = item.body ?? '';

    return ListTile(
      key: Key('review-item-${item.id}'),
      leading: CircleAvatar(
        backgroundColor: colors.warningSoft,
        foregroundColor: colors.warning,
        child: Text(_initials(name)),
      ),
      title: Row(
        children: [
          Expanded(child: Text(name)),
          Text(when, style: theme.textTheme.bodySmall),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (suggestion != null)
            Text(
              'Suggested: $suggestion',
              style: TextStyle(
                color: colors.successText,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      isThreeLine: true,
      onTap: () => context.push(AppRoutes.reviewMessage(item.id)),
    );
  }
}
