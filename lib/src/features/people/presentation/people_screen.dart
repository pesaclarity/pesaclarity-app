import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/people/people.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../sales/presentation/pay_sheet.dart' show methodName;
import '../../sales/presentation/records_sheets.dart';
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
    final services =
        ref.watch(businessSetupProvider).value?.sells == BusinessSells.services;
    final customerWord = services ? 'Clients' : 'Customers';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            TabHeader(
              services ? 'Clients' : 'People',
              semanticsId: SemanticIds.titlePeople,
              actions: [
                PillButton(
                  key: const Key('people-invoices'),
                  label: 'Invoices',
                  onPressed: () => context.push(AppRoutes.invoices),
                ),
                const SizedBox(width: 8),
                PillButton(
                  key: const Key('reminder-messages'),
                  label: 'Messages',
                  onPressed: () => context.push(AppRoutes.reminderMessages),
                ),
                const AmountsEye(),
              ],
            ),
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
    moneyOrHidden(minor, hidden: hidden, withCurrency: false);

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

class _Customers extends ConsumerWidget {
  const _Customers({required this.services});

  final bool services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hidden = AmountsHidden.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final customers = ref.watch(customersProvider);
    final all = customers.value;
    final word = services ? 'Clients' : 'Customers';
    if (customers.hasError && !customers.hasValue) {
      return ErrorView(
        'Your ${word.toLowerCase()} could not load.',
        onRetry: () => ref.invalidate(customersProvider),
      );
    }
    if (all == null) return const LoadingView(inList: true);
    final owing = [
      for (final c in all)
        if (c.owedMinor > 0) c,
    ];
    final total = owing.fold(0, (sum, c) => sum + c.owedMinor);
    final over = owing.fold(0, (sum, c) => sum + c.overTwoWeeksMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FigureRow(
          children: [
            FigureTile(label: 'They owe you', value: _plain(hidden, total)),
            FigureTile(label: 'Over 2 weeks', value: _plain(hidden, over)),
          ],
        ),
        const SizedBox(height: 12),
        if (owing.isEmpty)
          EmptyNote(
            '$word who pay later show here, with what they owe. Sell on '
            'credit to add one.',
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, c) in owing.indexed) ...[
                  if (i > 0) const Divider(height: 1),
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
                          style: AppTypography.rowAmount(
                            theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 10),
                        PillButton(
                          key: Key('remind-${c.name}'),
                          label: 'Remind',
                          onPressed: () => remindCustomer(context, ref, c),
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
    final amount = AppTypography.rowAmount(theme.colorScheme.onSurface);
    final hidden = AmountsHidden.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final suppliers = ref.watch(suppliersProvider);
    final owed = suppliers.value;
    final paid = ref.watch(suppliersPaidThisMonthProvider).value ?? const [];
    if (suppliers.hasError && !suppliers.hasValue) {
      return ErrorView(
        'Your suppliers could not load.',
        onRetry: () => ref.invalidate(suppliersProvider),
      );
    }
    if (owed == null) return const LoadingView(inList: true);
    final total = owed.fold(0, (sum, s) => sum + s.owedMinor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FigureRow(
          children: [
            FigureTile(label: 'You owe', value: _plain(hidden, total)),
            FigureTile(
              label: 'Due this week',
              value: _plain(hidden, dueWithin(owed, today: today)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (owed.isEmpty)
          const EmptyNote(
            'Suppliers you pay later show here. Use Bought on credit to '
            'add one.',
          )
        else
          Card(
            child: Column(
              children: [
                for (final (i, s) in owed.indexed) ...[
                  if (i > 0) const Divider(height: 1),
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
                    trailing: Text(_plain(hidden, s.owedMinor), style: amount),
                  ),
                ],
              ],
            ),
          ),
        if (paid.isNotEmpty) ...[
          const SectionLabel('Paid this month'),
          Card(
            child: Column(
              children: [
                for (final (i, p) in paid.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(p.supplier),
                    subtitle: Text(
                      'Paid by ${methodName(p.method)} on '
                      '${shortDate(CalendarDate.local(p.at))}',
                    ),
                    trailing: Text(
                      _plain(hidden, p.amountMinor),
                      style: amount,
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
