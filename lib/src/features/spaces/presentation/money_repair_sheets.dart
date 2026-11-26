import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/database/space_databases.dart';
import '../../../data/repositories/money_repair.dart';
import '../../../domain/spaces/money_between_spaces.dart';
import '../../../domain/spaces/space.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/application/balances_providers.dart';
import '../application/money_between_spaces_providers.dart';
import '../application/space_manager.dart';
import '../application/spaces_providers.dart';

/// The one-time repair of money between spaces (decision 0027, section 8),
/// run once when Personal opens after the update. Null in other spaces.
///
/// It waits for the repairs that run on opening ([pairHistoryOnceProvider]),
/// so Personal's copies of messages stored in two spaces are taken out
/// first and never at the same time; the repair itself does the other
/// spaces before it turns moves into the owner's account.
final moneyRepairProvider = FutureProvider<MoneyRepairState?>((ref) async {
  if (ref.watch(activeSpaceProvider).kind != SpaceKind.personal) return null;
  try {
    await ref.read(pairHistoryOnceProvider.future);
  } on Object {
    // The repair runs what it needs of it itself.
  }
  return ref.read(spaceManagerProvider).repairMoneyBetweenSpaces();
});

/// The first time the app opens after the update, over Personal's Home:
/// the sheet that says what the repair changed, then one question for each
/// business with a shared line. Nothing otherwise. Shown once.
Future<void> showMoneyRepair(
  BuildContext context,
  WidgetRef ref,
  MoneyRepairState? state,
) async {
  if (_shown ||
      state == null ||
      !state.ran ||
      state.shown ||
      state.result == null) {
    return;
  }
  _shown = true;
  final result = state.result!;
  final store = MoneyRepairStore(ref.read(personalDatabaseProvider));
  if (result.changedAnything) {
    await showAppSheet<void>(
      context: context,
      builder: (_) => AmountsHiddenScope(child: RepairResultSheet(result)),
    );
  }
  var left = result;
  for (final q in result.questions) {
    if (!context.mounted) return;
    final answered = await showAppSheet<bool>(
      context: context,
      builder: (_) => AmountsHiddenScope(child: RepairQuestionSheet(q)),
    );
    if (answered ?? false) left = left.withoutQuestion(q);
  }
  await store.save(MoneyRepairState(ran: true, shown: true, result: left));
}

/// Whether this run of the app has shown the repair already.
var _shown = false;

/// "Your records are put right": what the repair changed, what it removed
/// and what it could not settle.
class RepairResultSheet extends ConsumerWidget {
  const RepairResultSheet(this.result, {super.key});

  final MoneyRepairResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final names = ref.watch(spaceNamesProvider);
    String name(String id) => names[id] ?? 'Another space';
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    Widget row(String title, String detail, String value, Key key) => Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(detail, style: muted),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
    return SheetBody(
      title: 'Your records are put right',
      subtitle: 'Each payment now shows in one space',
      children: [
        for (final MapEntry(key: space, value: n) in result.switched.entries)
          row(
            'In ${name(space)} only',
            'Sales and costs on your M-Pesa',
            '$n',
            Key('repair-switched-$space'),
          ),
        for (final MapEntry(key: space, value: accounts)
            in result.removed.entries)
          for (final account in accounts)
            row(
              '$account in ${name(space)}',
              'Your $account lives in Personal',
              'Removed',
              Key('repair-removed-$space-$account'),
            ),
        if (result.unsettled > 0)
          row(
            'Could not settle',
            'From a space you deleted: back in Personal as your own',
            '${result.unsettled}',
            const Key('repair-unsettled'),
          ),
        const SizedBox(height: 8),
        // The sheet's subtitle style: at 13 px this line drew under 4.5:1 in
        // light, in any of the theme's text colours.
        Text(
          'A locked copy of each space is kept for 30 days.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('repair-next'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

/// "How much of your M-Pesa is Vegetable stall's today?", asked once for a
/// business whose M-Pesa balance the owner had typed (owner's decision 8).
class RepairQuestionSheet extends ConsumerStatefulWidget {
  const RepairQuestionSheet(this.question, {super.key});

  final RepairQuestion question;

  @override
  ConsumerState<RepairQuestionSheet> createState() =>
      _RepairQuestionSheetState();
}

class _RepairQuestionSheetState extends ConsumerState<RepairQuestionSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: (widget.question.suggestedMinor / 100).toStringAsFixed(0),
  );
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(String business) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final q = widget.question;
      final (db, close) = await ref
          .read(spaceDatabasesProvider)
          .open(q.spaceId);
      try {
        await setSpacePart(
          personal: ref.read(personalDatabaseProvider),
          business: db,
          businessId: q.spaceId,
          businessName: business,
          ownersAccountId: q.ownersAccountId,
          partMinor: AmountField.amountFrom(_amount.text) ?? 0,
          at: ref.read(clockProvider)(),
        );
      } finally {
        if (close) await db.close();
      }
      navigator.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final business =
        ref.watch(spaceNamesProvider)[q.spaceId] ?? 'Your business';
    final short = shortSpaceName(business);
    final wallet = ref
        .watch(balancesOverviewProvider)
        .value
        ?.accounts
        .where((a) => a.account.name == q.line)
        .firstOrNull
        ?.heldMinor;
    return Form(
      key: _form,
      child: SheetBody(
        title: "How much of your ${q.line} is $business's today?",
        subtitle:
            "You had typed the $short's ${q.line} balance. Its sales and "
            'costs on your ${q.line} add up to '
            '${shownMoney(context, q.suggestedMinor, withCurrency: true)}.',
        children: [
          AmountField(
            key: const Key('repair-part'),
            controller: _amount,
            label: 'Amount',
            allowZero: true,
          ),
          if (wallet != null) ...[
            const SizedBox(height: 12),
            Notice(
              'Your ${q.line} holds '
              '${shownMoney(context, wallet, withCurrency: true)}. The rest is '
              'yours.',
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('repair-part-save'),
            onPressed: _saving ? null : () => _save(business),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
