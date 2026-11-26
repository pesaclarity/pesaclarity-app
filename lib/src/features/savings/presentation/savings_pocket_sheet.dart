import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import 'savings_text.dart';

/// Opens the sheet for one goal of a savings account: its name, whether it
/// is locked and until when, and "This code is not mine".
Future<void> showSavingsPocketSheet(
  BuildContext context,
  SavingsPocket pocket,
) => showAppSheet<void>(
  context: context,
  builder: (context) => SavingsPocketSheet(pocket: pocket),
);

class SavingsPocketSheet extends ConsumerStatefulWidget {
  const SavingsPocketSheet({required this.pocket, super.key});

  final SavingsPocket pocket;

  @override
  ConsumerState<SavingsPocketSheet> createState() => _SavingsPocketSheetState();
}

class _SavingsPocketSheetState extends ConsumerState<SavingsPocketSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.pocket.name);
  late CalendarDate? _lockedUntil = widget.pocket.lockedUntil;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save({bool? ignored}) async {
    if (ignored == null && !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    await ref
        .read(savingsRepositoryProvider)
        .savePocket(
          widget.pocket.id,
          name: name.isEmpty ? widget.pocket.name : name,
          lockedUntil: _lockedUntil?.startInstant,
          ignored: ignored ?? widget.pocket.ignored,
        );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final pocket = widget.pocket;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return Form(
      key: _form,
      child: SheetBody(
        title: pocket.name,
        subtitle: pocket.hasCode ? pocket.code : SavingsText.noCode,
        children: [
          if (!pocket.ignored) ...[
            LabeledField(
              label: SavingsText.goalName,
              child: TextFormField(
                key: const Key('savings-pocket-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                validator: (text) => (text ?? '').trim().isEmpty
                    ? 'Enter a name, such as School fees.'
                    : null,
              ),
            ),
            LockUntilRow(
              value: _lockedUntil,
              today: today,
              onChanged: (day) => setState(() => _lockedUntil = day),
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('savings-pocket-save'),
              onPressed: _busy ? null : _save,
              child: const Text(SavingsText.save),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('savings-pocket-not-mine'),
              onPressed: _busy ? null : () => _save(ignored: true),
              child: Text(SavingsText.notMineCode(pocket.code)),
            ),
            Text(
              SavingsText.notMineNote,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall!
                  .copyWith(color: PesaColors.of(context).textMuted),
            ),
          ] else
            FilledButton(
              key: const Key('savings-pocket-mine'),
              onPressed: _busy ? null : () => _save(ignored: false),
              child: const Text(SavingsText.mineAfterAll),
            ),
        ],
      ),
    );
  }
}

/// "Locked until", with the day as a chip and a switch: switching it on
/// asks for the day. With large text the chip goes under the words.
class LockUntilRow extends StatelessWidget {
  const LockUntilRow({
    required this.value,
    required this.today,
    required this.onChanged,
    super.key,
  });

  /// The day it unlocks; null when it is open.
  final CalendarDate? value;
  final CalendarDate today;
  final ValueChanged<CalendarDate?> onChanged;

  Future<void> _pick(BuildContext context) async {
    DateTime asDay(CalendarDate d) => DateTime(d.year, d.month, d.day);
    final first = today.addDays(1);
    final last = CalendarDate(today.year + 30, 12, 31);
    final initial = value ?? today.addDays(30);
    final picked = await pickDate(
      context,
      initialDate: asDay(initial.isBefore(first) ? first : initial),
      firstDate: asDay(first),
      lastDate: asDay(last),
    );
    if (picked != null) {
      onChanged(CalendarDate(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final day = value;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 20, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Text(
                    SavingsText.lockedUntil,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (day != null)
                  PillButton(
                    icon: Icons.calendar_today_outlined,
                    label: dateLabel(day),
                    tooltip: 'Change the day it unlocks',
                    onPressed: () => _pick(context),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Layout.cardGap),
          Semantics(
            label: SavingsText.lockedUntil,
            child: Switch.adaptive(
              value: day != null,
              onChanged: (on) => on ? _pick(context) : onChanged(null),
            ),
          ),
        ],
      ),
    );
  }
}
