import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/enums.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/business_setup_providers.dart';

/// "What do you sell?": products, services or both. Then on to Start your
/// records, unless they have started already.
class WhatYouSellScreen extends ConsumerStatefulWidget {
  const WhatYouSellScreen({super.key});

  @override
  ConsumerState<WhatYouSellScreen> createState() => _WhatYouSellScreenState();
}

class _WhatYouSellScreenState extends ConsumerState<WhatYouSellScreen> {
  BusinessSells? _picked;

  Future<void> _continue(BusinessSells sells) async {
    await ref.read(businessSetupProvider.notifier).chooseSells(sells);
    if (!mounted) return;
    final started =
        ref.read(businessSetupProvider).value?.recordsStartedAt != null;
    context.go(started ? AppRoutes.home : AppRoutes.startRecords);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final saved = ref.watch(businessSetupProvider).value?.sells;
    final picked = _picked ?? saved ?? BusinessSells.products;

    return Scaffold(
      appBar: AppBar(title: const Text('What do you sell?')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'This sets up the right screens. You can change it later.',
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            RadioGroup<BusinessSells>(
              groupValue: picked,
              onChanged: (s) {
                if (s != null) setState(() => _picked = s);
              },
              child: Column(
                children: [
                  for (final (i, s) in BusinessSells.values.indexed) ...[
                    if (i > 0) const SizedBox(height: Layout.cardGap),
                    Card(
                      child: RadioListTile<BusinessSells>(
                        key: Key('sells-${s.name}'),
                        value: s,
                        title: Text(s.label),
                        subtitle: Text(s.hint),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Layout.cardGap),
            Card(
              child: ListTile(
                title: Text(switch (picked) {
                  BusinessSells.products => 'With Products you get',
                  BusinessSells.services => 'With Services you get',
                  BusinessSells.both => 'With Both you get',
                }),
                subtitle: Text(switch (picked) {
                  BusinessSells.products =>
                    'Selling by item, stock and restocking, customers and '
                        'suppliers, and profit',
                  BusinessSells.services =>
                    'Clients, your services and rates, income and costs, and '
                        'Pay yourself. No stock.',
                  BusinessSells.both =>
                    'Everything for products and services, with their profit '
                        'shown apart',
                }),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('sells-continue'),
              onPressed: () => _continue(picked),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Start your records: what the business has today, so its books start
/// right.
class StartRecordsScreen extends ConsumerStatefulWidget {
  const StartRecordsScreen({super.key});

  @override
  ConsumerState<StartRecordsScreen> createState() => _StartRecordsScreenState();
}

class _StartRecordsScreenState extends ConsumerState<StartRecordsScreen> {
  final _form = GlobalKey<FormState>();
  final _cash = TextEditingController();
  final _accounts = <int, TextEditingController>{};
  var _saving = false;

  @override
  void dispose() {
    _cash.dispose();
    for (final c in _accounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(OpeningLine line) =>
      _accounts.putIfAbsent(
        line.accountId,
        () => TextEditingController(
          text: line.suggestedMinor > 0 ? _plain(line.suggestedMinor) : '',
        ),
      );

  static String _plain(int minor) {
    final whole = minor ~/ 100;
    final cents = minor % 100;
    return cents == 0 ? '$whole' : '$whole.${cents.toString().padLeft(2, '0')}';
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(businessSetupProvider.notifier)
          .startRecords(
            cashMinor: AmountField.amountFrom(_cash.text) ?? 0,
            accounts: {
              for (final MapEntry(:key, :value) in _accounts.entries)
                key: AmountField.amountFrom(value.text) ?? 0,
            },
          );
      if (mounted) context.go(AppRoutes.home);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final loaded = ref.watch(openingLinesProvider);
    final lines = loaded.value;

    String labelFor(OpeningLine line) => switch (line.type) {
      AccountType.mpesa => 'On the business M-Pesa or till',
      _ => 'In the business bank account (${line.name})',
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Start your records')),
      body: SafeArea(
        child: loaded.hasError && !loaded.hasValue
            ? ErrorView(
                'Your accounts could not load.',
                onRetry: () => ref.invalidate(openingLinesProvider),
              )
            : lines == null
            ? const LoadingView()
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      'Tell us what the business has today, so the records '
                      'start right. You can change these later.',
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AmountField(
                      key: const Key('start-cash'),
                      controller: _cash,
                      label: 'Cash in the drawer',
                      allowZero: true,
                    ),
                    for (final line in lines) ...[
                      const SizedBox(height: 12),
                      AmountField(
                        key: Key('start-account-${line.accountId}'),
                        controller: _controllerFor(line),
                        label: labelFor(line),
                        allowZero: true,
                      ),
                      if (line.fromMessage)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
                          child: Text(
                            'We filled this in from your latest message.',
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 16),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            key: const Key('start-customers'),
                            title: const Text('Customers who owe you'),
                            subtitle: const Text('Add them now or later'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(AppRoutes.lending),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const Key('start-suppliers'),
                            title: const Text('Suppliers you owe'),
                            subtitle: const Text('Add them now or later'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(AppRoutes.debts),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('start-records'),
                      onPressed: _saving ? null : _start,
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
