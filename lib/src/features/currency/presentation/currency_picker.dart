import 'package:flutter/material.dart';

import '../../../core/money/currency_data.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/pesa_colors.dart';

/// A searchable list of every currency, with [suggested] (the phone
/// region's) on top. [subtitleOf] can add a line under a currency, such as
/// its rate.
class CurrencyPicker extends StatefulWidget {
  const CurrencyPicker({
    required this.selected,
    required this.onSelected,
    this.suggested,
    this.subtitleOf,
    this.header = const [],
    super.key,
  });

  final String selected;
  final String? suggested;
  final ValueChanged<String> onSelected;
  final String? Function(String code)? subtitleOf;

  /// Shown above the search field, scrolling with the list.
  final List<Widget> header;

  @override
  State<CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<CurrencyPicker> {
  var _query = '';

  bool _matches(String code) {
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
            title: Text(currencyCatalogue[code]!.name),
            subtitle: subtitle == null ? null : Text(subtitle),
            secondary: SizedBox(
              width: 44,
              child: Text(
                code,
                style: theme.textTheme.labelLarge!.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
