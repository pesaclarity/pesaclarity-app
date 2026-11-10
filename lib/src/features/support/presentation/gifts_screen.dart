import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/support_providers.dart';
import '../domain/support.dart';

/// A gift's amount, in shillings.
String giftAmount(BuildContext context, Gift gift) =>
    shownMoney(context, gift.amountMinor, currency: 'KES');

/// "Gift by M-Pesa", its day and M-Pesa code, and the amount.
class GiftRow extends ConsumerWidget {
  const GiftRow(this.gift, {super.key});

  final Gift gift;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final day = dayHeading(CalendarDate.local(gift.at), today: today);
    return ListTile(
      title: const Text('Gift by M-Pesa'),
      subtitle: Text([day, ?gift.code].join(' · ')),
      trailing: Text(
        giftAmount(context, gift),
        style: AppTypography.rowAmount(PesaColors.of(context).successText),
      ),
    );
  }
}

/// The person's own gifts, read from their M-Pesa messages and kept on the
/// phone.
class GiftsScreen extends ConsumerWidget {
  const GiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gifts = ref.watch(giftsProvider);
    final colors = PesaColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your gifts'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: AmountsHiddenScope(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Layout.gutter,
            8,
            Layout.gutter,
            Layout.screenBottom,
          ),
          children: [
            switch (gifts) {
              AsyncData(value: final list) when list.isEmpty => const EmptyNote(
                'Gifts you make by M-Pesa show here once their message '
                'comes in.',
              ),
              AsyncData(value: final list) => GroupedSection(
                footer:
                    'No goods or services were given in return. Kept on this '
                    'phone only.',
                children: [for (final g in list) GiftRow(g)],
              ),
              AsyncError() => ErrorView(
                'Your gifts could not load.',
                onRetry: () => ref.invalidate(giftsProvider),
              ),
              _ => const LoadingView(inList: true),
            },
            const SizedBox(height: 8),
            Text(
              'Giving never unlocks anything.',
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
