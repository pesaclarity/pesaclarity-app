import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/support_providers.dart';
import '../domain/support.dart';
import 'gifts_screen.dart';

/// The card under Home's red card that now and then asks for a coffee, and
/// the thank-you when a gift's M-Pesa message comes in. Only in the F-Droid
/// build, and never when [moneyTight].
class SupportHomeCard extends ConsumerStatefulWidget {
  const SupportHomeCard({required this.moneyTight, super.key});

  /// Today's money is spent, the plan is used up or a payment may not go
  /// through.
  final bool moneyTight;

  @override
  ConsumerState<SupportHomeCard> createState() => _SupportHomeCardState();
}

class _SupportHomeCardState extends ConsumerState<SupportHomeCard> {
  bool _starting = false;
  ProviderSubscription<Gift?>? _thanks;

  @override
  void initState() {
    super.initState();
    _thanks = ref.listenManual<Gift?>(giftToThankProvider, (_, gift) {
      if (gift == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _thank(gift));
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _thanks?.close();
    super.dispose();
  }

  Future<void> _thank(Gift gift) async {
    if (!mounted) return;
    // Marked first, so the sheet shows once even if Home rebuilds.
    await ref.read(supportStateProvider.notifier).markThanked(gift);
    if (!mounted) return;
    await showSupportThanks(context, gift);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(supportConfigProvider) == null) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(supportStateProvider).value;
    final gifts = ref.watch(giftsProvider).value;
    if (state == null || gifts == null) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final time = supportCardTime(
      state: state,
      now: now,
      moneyTight: widget.moneyTight,
      lastGiftAt: gifts.firstOrNull?.at,
    );
    if (time == SupportCardTime.hidden) return const SizedBox.shrink();
    if (time == SupportCardTime.startsNow && !_starting) {
      _starting = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(supportStateProvider.notifier).startShowing(now),
      );
    }
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Card(
        child: ListTile(
          key: const Key('home-support'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Layout.cardPadding,
            vertical: 4,
          ),
          leading: const IconBadge(Icons.coffee_outlined),
          title: const Text('Pesa Clarity is free'),
          subtitle: const Text(
            'No ads, no investors. If it helps you, buy us a coffee.',
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () {
            ref.read(supportStateProvider.notifier).rest();
            context.push(AppRoutes.support);
          },
        ),
      ),
    );
  }
}

/// Thanks the person for [gift], read from its own M-Pesa message.
Future<void> showSupportThanks(BuildContext context, Gift gift) =>
    showAppSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = PesaColors.of(context);
        return SheetBody(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.favorite_outline, color: colors.success),
              ),
            ),
            const SizedBox(height: 16),
            Text('Thank you', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Your ${giftAmount(context, gift)} reached us. It keeps Pesa '
              'Clarity free for you and everyone who uses it.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Card(child: GiftRow(gift)),
            const SizedBox(height: 12),
            Text(
              'No goods or services were given in return. Kept on this '
              'phone only.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('support-thanks-done'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
