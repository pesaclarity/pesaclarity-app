import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../domain/people/people.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../security/application/balance_visibility.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../application/people_providers.dart';
import 'remind_sheet.dart';

/// People tab: customers who owe the business, and suppliers it owes. A
/// services business calls its customers clients.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  var _customers = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services =
        ref.watch(businessSetupProvider).value?.sells == BusinessSells.services;
    final customerWord = services ? 'Clients' : 'Customers';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    services ? 'Clients' : 'People',
                    style: theme.textTheme.headlineLarge,
                  ),
                ),
                TextButton(
                  key: const Key('people-invoices'),
                  onPressed: () => context.push(AppRoutes.invoices),
                  child: Text(
                    'Invoices',
                    style: TextStyle(color: PesaColors.of(context).link),
                  ),
                ),
                TextButton(
                  key: const Key('reminder-messages'),
                  onPressed: () => context.push(AppRoutes.reminderMessages),
                  child: Text(
                    'Messages',
                    style: TextStyle(color: PesaColors.of(context).link),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: AdaptiveSegmented<bool>(
                showSelectedIcon: false,
                segments: [(true, customerWord), (false, 'Suppliers')],
                selected: _customers,
                onChanged: (v) => setState(() => _customers = v),
              ),
            ),
            const SizedBox(height: 16),
            if (_customers)
              _Customers(services: services)
            else
              const _Suppliers(),
          ],
        ),
      ),
    );
  }
}

String _plain(bool hidden, int minor) =>
    hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

/// Where a customer stands, in a few words: `Due today · since 29 Oct`.
String customerStanding(CustomerAccount c, {required CalendarDate today}) {
  final since = c.since;
  final due = c.nextDue;
  final first = c.overTwoWeeksMinor > 0
      ? 'Over 2 weeks'
      : due == null
      ? null
      : due == today
      ? 'Due today'
      : 'Due ${dayLabel(due, thisYear: today.year)}';
  return [?first, if (since != null) 'since ${shortDate(since)}'].join(' · ');
}

/// Opens the Remind sheet for [c].
Future<void> remindCustomer(
  BuildContext context,
  WidgetRef ref,
  CustomerAccount c,
) => showRemindSheet(context, c);

/// Steps through everyone due today or late, or owing over two weeks, one
/// Remind sheet at a time; stops when one is closed.
Future<void> remindAllDue(
  BuildContext context,
  List<CustomerAccount> customers, {
  required CalendarDate today,
}) async {
  for (final c in dueCustomers(customers, today: today)) {
    if (!context.mounted) return;
    final sent = await showRemindSheet(context, c);
    if (sent != true) return;
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles(this.tiles);

  final List<(String, String)> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Row(
      children: [
        for (final (i, (label, value)) in tiles.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
                side: BorderSide(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: AppTypography.amount(
                        size: 20,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Customers extends ConsumerWidget {
  const _Customers({required this.services});

  final bool services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = ref.watch(balancesHiddenProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final all = ref.watch(customersProvider).value;
    if (all == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final owing = [
      for (final c in all)
        if (c.owedMinor > 0) c,
    ];
    final total = owing.fold(0, (sum, c) => sum + c.owedMinor);
    final over = owing.fold(0, (sum, c) => sum + c.overTwoWeeksMinor);
    final word = services ? 'Clients' : 'Customers';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tiles([
          ('They owe you', _plain(hidden, total)),
          ('Over 2 weeks', _plain(hidden, over)),
        ]),
        const SizedBox(height: 12),
        if (owing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '$word who pay later show here, with what they owe. Sell on '
              'credit to add one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, c) in owing.indexed) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    key: Key('customer-${c.name}'),
                    onTap: () =>
                        context.push(AppRoutes.customerStatement(c.name)),
                    title: Text(c.name),
                    subtitle: Text(customerStanding(c, today: today)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _plain(hidden, c.owedMinor),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          key: Key('remind-${c.name}'),
                          onPressed: () => remindCustomer(context, ref, c),
                          child: const Text('Remind'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (dueCustomers(owing, today: today).isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('remind-all'),
            onPressed: () => remindAllDue(context, owing, today: today),
            child: const Text('Remind all who are due'),
          ),
        ],
      ],
    );
  }
}

class _Suppliers extends ConsumerWidget {
  const _Suppliers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = ref.watch(balancesHiddenProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final owed = ref.watch(suppliersProvider).value;
    final paid = ref.watch(suppliersPaidThisMonthProvider).value ?? const [];
    if (owed == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final total = owed.fold(0, (sum, s) => sum + s.owedMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tiles([
          ('You owe', _plain(hidden, total)),
          ('Due this week', _plain(hidden, dueWithin(owed, today: today))),
        ]),
        const SizedBox(height: 12),
        if (owed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Suppliers you pay later show here. Use Bought on credit to '
              'add one.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, s) in owed.indexed) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    key: Key('supplier-${s.debt.id}'),
                    onTap: () =>
                        context.push(AppRoutes.supplierStatement(s.debt.id)),
                    title: Text(s.name),
                    subtitle: s.nextDue == null
                        ? null
                        : Text(
                            s.nextDue == today
                                ? 'Due today'
                                : 'Due ${dayLabel(s.nextDue!, thisYear: today.year)}',
                          ),
                    trailing: Text(
                      _plain(hidden, s.owedMinor),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (paid.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
            child: Text(
              'PAID THIS MONTH',
              style: theme.textTheme.labelLarge!.copyWith(
                color: colors.textMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, p) in paid.indexed) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(p.supplier),
                    subtitle: Text(
                      'Paid by ${methodName(p.method)} on '
                      '${shortDate(CalendarDate.local(p.at))}',
                    ),
                    trailing: Text(
                      _plain(hidden, p.amountMinor),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('bought-on-credit'),
          onPressed: () => showBoughtSheet(context, payLater: true),
          child: const Text('Bought on credit'),
        ),
      ],
    );
  }
}
