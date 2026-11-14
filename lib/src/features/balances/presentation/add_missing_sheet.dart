import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';

/// What a payment missing from a gap was, and how it goes in the ledger.
enum MissingKind {
  sentToSomeone(TransactionKind.sent, null, out: true),
  airtime(TransactionKind.airtime, 'airtime_data', out: true),
  fulizaRepayment(
    TransactionKind.fulizaRepayment,
    'fuliza_repayment',
    out: true,
  ),
  fees(TransactionKind.charge, 'fees_charges', out: true),
  loanRepayment(TransactionKind.sent, 'loan_repayment', out: true),
  otherOut(TransactionKind.sent, null, out: true),
  receivedFromSomeone(TransactionKind.received, 'money_received', out: false),
  refund(TransactionKind.reversal, null, out: false),
  otherIn(TransactionKind.received, null, out: false);

  const MissingKind(this.kind, this.categoryKey, {required this.out});

  final TransactionKind kind;

  /// The seeded category it is filed under; null leaves it to the payee.
  final String? categoryKey;

  /// Whether it is money out.
  final bool out;

  static List<MissingKind> forDirection({required bool out}) => [
    for (final k in values)
      if (k.out == out) k,
  ];
}

/// When a missing payment between [gap]'s two balances is placed: half way
/// between them.
DateTime missingAt(BalanceGap gap) {
  final from = gap.from.occurredAt;
  final to = gap.to.occurredAt;
  return from.add(
    Duration(microseconds: to.difference(from).inMicroseconds ~/ 2),
  );
}

/// "Add what's missing": the gap as a real transaction, with what it was.
Future<void> showAddMissingSheet(
  BuildContext context,
  BalanceGap gap,
  AccountBalance balance,
) => showAppSheet<void>(
  context: context,
  builder: (context) => AddMissingSheet(gap: gap, balance: balance),
);

class AddMissingSheet extends ConsumerStatefulWidget {
  const AddMissingSheet({required this.gap, required this.balance, super.key});

  final BalanceGap gap;
  final AccountBalance balance;

  @override
  ConsumerState<AddMissingSheet> createState() => _AddMissingSheetState();
}

class _AddMissingSheetState extends ConsumerState<AddMissingSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _who = TextEditingController();
  late bool _out = widget.gap.gapMinor < 0;
  late MissingKind _kind = MissingKind.forDirection(out: _out).first;
  var _saving = false;

  String get _currency => widget.balance.opening.currency;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: formatMoney(
        Money(widget.gap.gapMinor.abs(), currency: _currency),
        withCurrency: false,
      ),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _who.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseMoneyMinor(_amount.text, currency: _currency)!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final key = _kind.categoryKey;
    final categoryId = key == null
        ? null
        : (await ref.read(categoriesRepositoryProvider).byKey(key))?.id;
    final who = _who.text.trim();
    final fee = _kind == MissingKind.fees;
    await ref
        .read(transactionsRepositoryProvider)
        .add(
          TransactionsCompanion.insert(
            accountId: widget.gap.accountId,
            occurredAt: missingAt(widget.gap),
            amountMinor: amount,
            direction: _out
                ? TransactionDirection.outflow
                : TransactionDirection.inflow,
            kind: Value(_kind.kind),
            currency: Value(_currency),
            source: TransactionSource.manual,
            counterpartyName: Value(
              who.isEmpty ? (fee ? BalanceText.missingFees : null) : who,
            ),
            categoryOverrideId: Value(categoryId),
          ),
        );
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text(BalanceText.missingAdded)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final gap = widget.gap;
    String when(DateTime t) =>
        '${dayHeading(CalendarDate.local(t), today: today)} ${formatTime(t)}';
    final kinds = MissingKind.forDirection(out: _out);
    return Form(
      key: _form,
      child: SheetBody(
        title: BalanceText.addWhatsMissing,
        subtitle: BalanceText.addMissingIntro(widget.balance.account.name),
        children: [
          AdaptiveSegmented<bool>(
            segments: const [
              (true, BalanceText.moneyOut),
              (false, BalanceText.moneyIn),
            ],
            selected: _out,
            onChanged: (value) => setState(() {
              _out = value;
              _kind = MissingKind.forDirection(out: value).first;
            }),
          ),
          const SizedBox(height: 16),
          AmountField(
            key: const Key('add-missing-amount'),
            controller: _amount,
            label: BalanceText.amount,
            currency: _currency,
          ),
          const SizedBox(height: 12),
          Text(
            BalanceText.whatWasIt,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 4),
          ChoiceMenu<MissingKind>(
            key: const Key('add-missing-kind'),
            name: BalanceText.whatWasIt,
            expand: true,
            options: [for (final k in kinds) (k, BalanceText.missingKind(k))],
            value: _kind,
            itemKey: (k) => Key('add-missing-kind-${k.name}'),
            onChanged: (k) => setState(() => _kind = k),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('add-missing-who'),
            controller: _who,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _out ? BalanceText.paidTo : BalanceText.receivedFrom,
              hintText: BalanceText.optional,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            BalanceText.placedBetween(
              when(gap.from.occurredAt),
              when(gap.to.occurredAt),
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('add-missing-save'),
            onPressed: _saving ? null : _save,
            child: const Text(BalanceText.addIt),
          ),
        ],
      ),
    );
  }
}
