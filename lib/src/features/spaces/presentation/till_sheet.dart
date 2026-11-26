import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/spaces/line_routing.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../documents/application/document_providers.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';

/// "Till 123456", "Paybill 400200".
String channelLabel(ChannelKind kind, String number) =>
    '${kind == ChannelKind.paybill ? 'Paybill' : 'Till'} $number';

/// Your business's till or paybill (decision 0027, section 4; owner's
/// decision 17): typed, or read from how the owner already tells customers
/// to pay on invoices. Money in through it then goes to the business with
/// no question.
Future<void> showTillSheet(BuildContext context, {required String line}) =>
    showAppSheet<void>(
      context: context,
      builder: (_) => _TillSheet(line: line),
    );

class _TillSheet extends ConsumerStatefulWidget {
  const _TillSheet({required this.line});

  final String line;

  @override
  ConsumerState<_TillSheet> createState() => _TillSheetState();
}

class _TillSheetState extends ConsumerState<_TillSheet> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  var _kind = ChannelKind.till;
  var _saving = false;
  String? _note;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  /// Reads the till or paybill the invoices already show customers.
  Future<void> _readFromInvoices() async {
    final settings = await ref.read(documentSettingsProvider.future);
    final found = channelFromPayLine(settings.till);
    setState(() {
      if (found == null) {
        _note =
            'No till or paybill on your invoices yet. Type the number '
            'instead.';
        return;
      }
      _note = null;
      _kind = found.$1;
      _number.text = found.$2;
    });
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final space = ref.read(activeSpaceProvider);
      final rules = await ref.read(routingRulesProvider.future);
      await ref
          .read(routingRulesProvider.notifier)
          .setChannels(
            widget.line,
            rules
                .channelsOn(widget.line)
                .withNumber(_kind, _number.text.trim(), space.id),
          );
      ref.invalidate(sharedLineQuestionsProvider);
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = ref.watch(activeSpaceProvider);
    return Form(
      key: _form,
      child: SheetBody(
        title: "Your business's till or paybill",
        subtitle:
            'Money in through it goes to ${space.name} without a question.',
        children: [
          LabeledField(
            label: 'Kind',
            child: ChoiceMenu<ChannelKind>(
              key: const Key('till-kind'),
              name: 'Kind',
              expand: true,
              value: _kind,
              options: const [
                (ChannelKind.till, 'Till (Buy Goods)'),
                (ChannelKind.paybill, 'Paybill'),
              ],
              itemKey: (k) => Key('till-kind-${k.name}'),
              onChanged: (k) => setState(() => _kind = k),
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'Number',
            child: TextFormField(
              key: const Key('till-number'),
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => v == null || v.trim().length < 5
                  ? 'Enter the number, such as 123456.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('till-read-qr'),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Read from your M-PESA QR code'),
            onPressed: _readFromInvoices,
          ),
          if (_note case final note?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Notice(note, key: const Key('till-read-note')),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('till-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
