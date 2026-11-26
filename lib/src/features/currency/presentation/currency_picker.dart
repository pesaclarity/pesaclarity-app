import 'package:material_ui/material_ui.dart';

import '../../../core/money/currency_data.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/beside_or_under.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/pesa_colors.dart';

/// A searchable list of every currency, with [suggested] (the phone
/// region's) on top. [subtitleOf] can add a line under a currency, such as
/// its rate.
///
/// With [withNone], None comes first: it is [CurrencyPicker.none], and
/// selected while [selected] is.
class CurrencyPicker extends StatefulWidget {
  const CurrencyPicker({
    required this.selected,
    required this.onSelected,
    this.suggested,
    this.subtitleOf,
    this.header = const [],
    this.withNone = false,
    this.leaveOut = const {},
    super.key,
  });

  /// The value of None, with [withNone].
  static const none = '';

  final String selected;
  final String? suggested;
  final ValueChanged<String> onSelected;
  final bool withNone;

  /// Currencies not offered, such as the main one when picking a second.
  final Set<String> leaveOut;
  final String? Function(String code)? subtitleOf;

  /// Shown above the search field, scrolling with the list.
  final List<Widget> header;

  @override
  State<CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<CurrencyPicker> {
  var _query = '';

  bool _matches(String code) {
    if (widget.leaveOut.contains(code)) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return code.toLowerCase().contains(q) ||
        currencyCatalogue[code]!.name.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final suggested = widget.suggested;
    final top = {
      ?suggested,
      widget.selected,
    }.where((c) => currencyCatalogue.containsKey(c) && _matches(c)).toList();
    final rest = [
      for (final code in currencyCatalogue.keys)
        if (!top.contains(code) && _matches(code)) code,
    ];

    Widget tile(String code) {
      final subtitle = widget.subtitleOf?.call(code);
      // Merged so the id lands on the node that carries the checked state.
      return MergeSemantics(
        child: Semantics(
          identifier: SemanticIds.currency(code),
          child: RadioListTile<String>(
            key: Key('currency-$code'),
            value: code,
            // The code at the end, or under the name at larger text, so no
            // word of either is broken over two lines.
            title: BesideOrUnder(
              gap: 12,
              lead: Text(currencyCatalogue[code]!.name),
              end: Text(
                code,
                style: theme.textTheme.labelLarge!.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
          ),
        ),
      );
    }

    return RadioGroup<String>(
      groupValue: widget.selected,
      onChanged: (code) {
        if (code != null) widget.onSelected(code);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          ...widget.header,
          TextField(
            key: const Key('currency-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name or code',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          if (widget.withNone && _query.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Card(
                child: MergeSemantics(
                  child: RadioListTile<String>(
                    key: Key('currency-none'),
                    value: CurrencyPicker.none,
                    title: Text('None'),
                  ),
                ),
              ),
            ),
          if (top.isNotEmpty) ...[
            SectionLabel(
              suggested != null && top.contains(suggested)
                  ? "From your phone's region"
                  : 'Your currency',
            ),
            Card(child: Column(children: [for (final c in top) tile(c)])),
          ],
          if (rest.isNotEmpty) ...[
            const SectionLabel('All currencies'),
            Card(child: Column(children: [for (final c in rest) tile(c)])),
          ],
        ],
      ),
    );
  }
}

/// Asks for a second currency to show beside [main], on its own page with
/// None first. A record with the code (null for None) once one is picked;
/// null when the person goes back without picking.
Future<({String? code})?> pickSecondCurrency(
  BuildContext context, {
  required String? selected,
  required String main,
}) async {
  final picked = await Navigator.of(context).push(
    MaterialPageRoute<String>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Second currency')),
        body: CurrencyPicker(
          selected: selected ?? CurrencyPicker.none,
          withNone: true,
          leaveOut: {main},
          onSelected: (code) => Navigator.of(context).pop(code),
          header: [
            Text(
              'Shown beside $main on Home, at the day\'s rate, and first in '
              'the converter.',
              style: Theme.of(context).textTheme.bodyLarge!
                  .copyWith(color: PesaColors.of(context).textMuted),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  if (picked == null) return null;
  return (code: picked == CurrencyPicker.none ? null : picked);
}
