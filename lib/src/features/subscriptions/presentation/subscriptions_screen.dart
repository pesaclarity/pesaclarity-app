import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/subscriptions_repository.dart';
import '../../../domain/reminders/recurring_charges.dart';
import '../../../domain/reminders/reminder_settings.dart';
import '../../../domain/subscriptions/subscriptions.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../../theme/pesa_colors.dart';
import '../../reminders/application/reminders_controller.dart';
import '../application/subscriptions_providers.dart';

String _amount(int minor) => formatMoney(Money(minor), withCurrency: false);

const frequencyLabels = {
  RecurrenceFrequency.weekly: 'Every week',
  RecurrenceFrequency.monthly: 'Every month',
  RecurrenceFrequency.quarterly: 'Every three months',
  RecurrenceFrequency.yearly: 'Every year',
};

/// Profile › Subscriptions: what repeats, what it costs, and repeat charges
/// found in messages that are worth tracking.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(subscriptionsOverviewProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          IconButton(
            tooltip: 'Add a subscription',
            icon: const Icon(Icons.add),
            onPressed: () => showSubscriptionSheet(context),
          ),
        ],
      ),
      body: switch (overview) {
        AsyncData(:final value) => _Body(value, today: today),
        AsyncError() => const Center(
          child: Text('Subscriptions did not load. Open them again.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.overview, {required this.today});

  final SubscriptionsOverview overview;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final next = overview.next;
    final reminders = ref.watch(remindersControllerProvider).value;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        HeroFigureCard(
          label: overview.lines.isEmpty
              ? 'Nothing tracked yet'
              : '${overview.lines.length} active · every month',
          figure: '${overview.currency} ${_amount(overview.monthlyTotalMinor)}',
          caption: next == null
              ? 'Add one, or track a charge found in your messages.'
              : '${_amount(overview.yearlyTotalMinor)} a year · next: '
                    '${next.subscription.name} '
                    '${relativeDays(next.nextDate, today: today)}',
        ),
        for (final charge in overview.suggestions) ...[
          const SizedBox(height: 12),
          _SuggestionCard(charge),
        ],
        if (overview.lines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final (i, line) in overview.lines.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(line.subscription.name),
                    subtitle: Text(
                      line.previousAmountMinor == null
                          ? '${frequencyLabels[line.subscription.frequency]} · '
                                '${shortDate(line.nextDate)}'
                          : 'Now ${_amount(line.amountMinor)}, was '
                                '${_amount(line.previousAmountMinor!)} · '
                                '${shortDate(line.nextDate)}',
                      style: line.previousAmountMinor == null
                          ? null
                          : TextStyle(color: colors.warning),
                    ),
                    trailing: Text(
                      _amount(line.amountMinor),
                      style: theme.textTheme.titleMedium,
                    ),
                    onTap: () => showSubscriptionSheet(
                      context,
                      subscription: line.subscription,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            key: const Key('subscription-reminders'),
            title: Text(
              reminders == null
                  ? 'Remind me before each charge'
                  : 'Remind me ${leadDaysLabel(reminders.leadDays).toLowerCase()}',
            ),
            value: (reminders?.enabled ?? false) && reminders!.cardCharges,
            onChanged: reminders == null
                ? null
                : (on) async {
                    final controller = ref.read(
                      remindersControllerProvider.notifier,
                    );
                    if (on &&
                        !reminders.enabled &&
                        !await controller.setEnabled(true)) {
                      return;
                    }
                    await controller.change((s) => s.copyWith(cardCharges: on));
                  },
          ),
        ),
      ],
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard(this.charge);

  final RecurringCharge charge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repository = ref.read(subscriptionsRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'FOUND IN YOUR MESSAGES',
              style: theme.textTheme.labelMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(charge.name, style: theme.textTheme.titleMedium),
            Text(
              '${_amount(charge.amountMinor)} on the ${charge.lastDate.day}, '
              'two months running',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => repository.dismiss(charge),
                    child: const Text('One-off'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => repository.track(charge),
                    child: const Text('Track it'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the form to add a subscription, or to edit [subscription].
Future<void> showSubscriptionSheet(
  BuildContext context, {
  Subscription? subscription,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SubscriptionForm(subscription: subscription),
);

class SubscriptionForm extends ConsumerStatefulWidget {
  const SubscriptionForm({this.subscription, super.key});

  final Subscription? subscription;

  @override
  ConsumerState<SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends ConsumerState<SubscriptionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late RecurrenceFrequency _frequency;
  late CalendarDate _nextDate;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.subscription;
    _name = TextEditingController(text: s?.name ?? '');
    _amount = TextEditingController(
      text: s == null
          ? ''
          : formatMoney(Money(s.amountMinor), withCurrency: false),
    );
    _frequency = s?.frequency ?? RecurrenceFrequency.monthly;
    _nextDate = s?.nextDate ?? CalendarDate.local(ref.read(clockProvider)());
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repository = ref.read(subscriptionsRepositoryProvider);
    final amount = parseMoneyMinor(_amount.text)!;
    final s = widget.subscription;
    if (s == null) {
      await repository.add(
        name: _name.text,
        amountMinor: amount,
        frequency: _frequency,
        nextDate: _nextDate,
      );
    } else {
      await repository.update(
        Subscription(
          id: s.id,
          name: _name.text,
          payeeId: s.payeeId,
          amountMinor: amount,
          currency: s.currency,
          frequency: _frequency,
          nextDate: _nextDate,
          status: s.status,
        ),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    await ref
        .read(subscriptionsRepositoryProvider)
        .remove(widget.subscription!.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_nextDate.year, _nextDate.month, _nextDate.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(
      () => _nextDate = CalendarDate(picked.year, picked.month, picked.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.subscription != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  editing ? 'Edit subscription' : 'Add a subscription',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('subscription-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('subscription-amount'),
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText:
                        '${widget.subscription?.currency ?? BaseCurrency.code} ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) => parseMoneyMinor(v ?? '') == null
                      ? 'Enter an amount, such as 300'
                      : null,
                ),
                const SizedBox(height: 16),
                SelectorField(
                  label: 'How often',
                  value: frequencyLabels[_frequency]!,
                  onTap: () async {
                    final picked = await showOptionSheet<RecurrenceFrequency>(
                      context,
                      title: 'How often',
                      options: [
                        for (final MapEntry(:key, :value)
                            in frequencyLabels.entries)
                          (key, value),
                      ],
                      selected: _frequency,
                    );
                    if (picked != null) setState(() => _frequency = picked);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Next charge'),
                  subtitle: Text(longDate(_nextDate)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: const Text('Save'),
                ),
                if (editing) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _remove,
                    child: const Text('Stop tracking'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
