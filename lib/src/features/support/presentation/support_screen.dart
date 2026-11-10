import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/support_providers.dart';
import '../domain/support.dart';

/// Gifts are in shillings, whatever the base currency.
const _giftCurrency = 'KES';

/// Support Pesa Clarity: why gifts help, a one-time gift by M-Pesa, the
/// person's own gifts and "Don't ask me again".
class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  /// Null means another amount, typed below.
  int? _amount = supportDefaultAmount;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  /// The amount to give in shillings, or null until one is typed.
  int? get _shillings {
    if (_amount case final amount?) return amount;
    final minor = parseMoneyMinor(_other.text, currency: _giftCurrency);
    if (minor == null || minor < 100) return null;
    return minor ~/ 100;
  }

  String _plain(int shillings) => formatMoney(
    Money.major(shillings, currency: _giftCurrency),
    withCurrency: false,
  );

  Future<void> _give(SupportConfig config) async {
    final opened = await ref
        .read(supportOpenerProvider)
        .open(config.link(config.takesAmount ? _shillings : null));
    if (!opened && mounted) {
      showNote(context, 'No browser could open the page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(supportConfigProvider);
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    if (config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Support Pesa Clarity')),
        body: const EmptyNote('Giving is on the website.'),
      );
    }
    final state = ref.watch(supportStateProvider).value;
    final gifts = ref.watch(giftsProvider).value ?? const [];
    final shillings = _shillings;
    final amountsOther = [
      for (final a in supportAmounts) (a as int?, _plain(a)),
      (null, 'Other amount'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Support Pesa Clarity')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Layout.gutter,
          8,
          Layout.gutter,
          Layout.screenBottom,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconBadge(Icons.coffee_outlined),
                  const SizedBox(height: 12),
                  Text(
                    'Free, and it stays free',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pesa Clarity has no ads and no investors, and your '
                    'money data stays on your phone. Gifts from people who '
                    'use it pay for the stores, the website and the time it '
                    'takes.',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Giving never unlocks anything. Every feature is free '
                    'for everyone.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SectionLabel('Buy us a coffee'),
          if (config.takesAmount) ...[
            Card(
              child: ListTile(
                title: const Text('Amount'),
                trailing: ChoiceMenu<int?>(
                  key: const Key('support-amount'),
                  name: 'Amount',
                  options: amountsOther,
                  value: _amount,
                  itemKey: (a) => Key('support-amount-${a ?? 'other'}'),
                  onChanged: (a) => setState(() => _amount = a),
                ),
              ),
            ),
            if (_amount == null) ...[
              const SizedBox(height: 12),
              AmountField(
                key: const Key('support-other'),
                controller: _other,
                label: 'Amount',
                currency: _giftCurrency,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                'Choose ${supportAmounts.map(_plain).join(', ')} shillings '
                'or any amount on the next page.',
                style: muted,
              ),
            ),
          FilledButton(
            key: const Key('support-give'),
            onPressed: config.takesAmount && shillings == null
                ? null
                : () => _give(config),
            child: Text(
              config.takesAmount && shillings != null
                  ? 'Give ${_plain(shillings)} with M-Pesa'
                  : 'Give with M-Pesa',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Opens the giving page in your browser. M-Pesa asks for your PIN '
            'as usual. Nothing from the app is shared.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 20),
          GroupedSection(
            children: [
              if (config.costs case final costs?)
                ListTile(
                  key: const Key('support-costs'),
                  title: const Text('What it costs'),
                  subtitle: const Text('Where gifts go, on the website'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ref.read(supportOpenerProvider).open(costs),
                ),
              if (config.knowsGifts)
                ListTile(
                  key: const Key('support-gifts'),
                  title: const Text('Your gifts'),
                  subtitle: Text(
                    gifts.isEmpty
                        ? 'Read from their M-Pesa messages'
                        : gifts.length == 1
                        ? '1 gift'
                        : '${gifts.length} gifts',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.supportGifts),
                ),
              SwitchListTile.adaptive(
                key: const Key('support-dont-ask'),
                title: const Text("Don't ask me again"),
                subtitle: const Text('The card on Home stops showing'),
                value: state?.optedOut ?? false,
                onChanged: state == null
                    ? null
                    : (on) => ref
                          .read(supportStateProvider.notifier)
                          .setOptedOut(on),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Notice(
            'We never call you, never send an M-Pesa request you didn\'t '
            'start, and never ask for your PIN.',
            icon: Icons.lock_outline,
          ),
        ],
      ),
    );
  }
}
