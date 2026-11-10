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
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../reminders/application/reminders_controller.dart';
import '../application/subscriptions_providers.dart';

String _amount(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: false);

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
          AddButton(
            tooltip: 'Add a subscription',
            onPressed: () => showSubscriptionSheet(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: switch (overview) {
        AsyncData(:final value) => _Body(value, today: today),
        AsyncError() => ErrorView(
          'Your subscriptions could not load.',
          onRetry: () => ref.invalidate(subscriptionsOverviewProvider),
        ),
        _ => const LoadingView(),
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
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        8,
        Layout.gutter,
        Layout.screenBottom,
      ),
      children: [
        if (next == null)
          const HeroFigureCard(
            label: 'Every month',
            caption:
                'Add a subscription, or track a charge found in your '
                'messages, to see what they cost each month.',
          )
        else
          HeroFigureCard(
            label: '${overview.lines.length} active · every month',
            figure: shownMoney(
              context,
              overview.monthlyTotalMinor,
              currency: overview.currency,
              withCurrency: true,
            ),
            caption:
                '${_amount(context, overview.yearlyTotalMinor)} a year · next: '
                '${next.subscription.name} '
                '${relativeDays(next.nextDate, today: today)}',
          ),
        if (overview.suggestions.isNotEmpty) ...[
          const SectionLabel('Found in your messages'),
          for (final (i, charge) in overview.suggestions.indexed) ...[
            if (i > 0) const SizedBox(height: Layout.cardGap),
            _SuggestionCard(charge),
          ],
        ],
        if (overview.lines.isNotEmpty) ...[
          const SizedBox(height: Layout.cardGap),
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
                          : 'Now ${_amount(context, line.amountMinor)}, was '
                                '${_amount(context, line.previousAmountMinor!)} · '
                                '${shortDate(line.nextDate)}',
                      style: line.previousAmountMinor == null
                          ? null
                          : TextStyle(color: colors.warning),
                    ),
                    trailing: Text(
                      _amount(context, line.amountMinor),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
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
        const SizedBox(height: Layout.cardGap),
        Card(
          child: SwitchListTile.adaptive(
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

/// A repeat charge found in messages: tapping it asks whether to track it.
class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard(this.charge);

  final RecurringCharge charge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(subscriptionsRepositoryProvider);
    final detail =
        '${_amount(context, charge.amountMinor)} on the '
        '${charge.lastDate.day}, two months running';
    return Card(
      child: ListTile(
        title: Text(charge.name),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showAppSheet<void>(
          context: context,
          builder: (context) => SheetBody(
            title: charge.name,
            subtitle: '$detail. Track it to see it here each month.',
            children: [
              ButtonPair(
                primary: FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    repository.track(charge);
                  },
                  child: const Text('Track it'),
                ),
                secondary: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    repository.dismiss(charge);
                  },
                  child: const Text('One-off'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the form to add a subscription, or to edit [subscription].
Future<void> showSubscriptionSheet(
  BuildContext context, {
  Subscription? subscription,
}) => showAppSheet<void>(
  context: context,
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
          : formatMoney(
              Money(s.amountMinor, currency: s.currency),
              withCurrency: false,
            ),
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
    final amount = AmountField.amountFrom(_amount.text)!;
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
    final s = widget.subscription!;
    final sure = await confirmDelete(
      context,
      title: 'Delete ${s.name}?',
      body: 'Its payments stay in Activity.',
    );
    if (!sure || !mounted) return;
    setState(() => _saving = true);
    await ref
        .read(subscriptionsRepositoryProvider)
        .remove(widget.subscription!.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.subscription != null;
    return Form(
      key: _formKey,
      child: SheetBody(
        title: editing ? 'Edit subscription' : 'Add a subscription',
        children: [
          TextFormField(
            key: const Key('subscription-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 80,
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Enter a name, such as Netflix.'
                : null,
          ),
          const SizedBox(height: 8),
          AmountField(
            key: const Key('subscription-amount'),
            controller: _amount,
            label: 'Amount',
            currency: widget.subscription?.currency,
          ),
          const SizedBox(height: 16),
          Text(
            'How often',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 8),
          ChoiceMenu<RecurrenceFrequency>(
            key: const Key('subscription-frequency'),
            name: 'How often',
            expand: true,
            options: [
              for (final MapEntry(:key, :value) in frequencyLabels.entries)
                (key, value),
            ],
            value: _frequency,
            onChanged: (value) => setState(() => _frequency = value),
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Next charge',
            value: _nextDate,
            firstDate: CalendarDate(2000, 1, 1),
            lastDate: CalendarDate(2100, 12, 31),
            onChanged: (date) {
              if (date != null) setState(() => _nextDate = date);
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          if (editing) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Delete subscription'),
            ),
          ],
        ],
      ),
    );
  }
}
