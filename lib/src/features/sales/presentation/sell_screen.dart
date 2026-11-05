import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../routing/app_shell.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import 'pay_sheet.dart';

/// Sell: the amount of a sale typed on a number pad, then Pay. Items join
/// with stock.
class SellScreen extends StatefulWidget {
  const SellScreen({this.billed = false, super.key});

  /// Work done for a client to pay later: Billed, with credit to start.
  final bool billed;

  /// The most whole shillings a sale can be keyed in as.
  static const maxDigits = 9;

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  var _digits = '';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _minor => _digits.isEmpty ? 0 : int.parse(_digits) * 100;

  String get _what => widget.billed ? 'Work done' : 'Other sale';

  void _press(String key) => setState(() {
    if (key == '⌫') {
      if (_digits.isNotEmpty) {
        _digits = _digits.substring(0, _digits.length - 1);
      }
      return;
    }
    final next = (_digits + key).replaceFirst(RegExp('^0+'), '');
    if (next.length <= SellScreen.maxDigits) _digits = next;
  });

  Future<void> _pay() async {
    final note = _note.text.trim();
    final saved = await showPaySheet(
      context,
      totalMinor: _minor,
      note: note.isEmpty ? null : note,
      initialWay: widget.billed ? PayWay.credit : PayWay.cash,
    );
    if (saved == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final amount = formatMoney(Money(_minor));

    return Scaffold(
      appBar: AppBar(title: Text(widget.billed ? 'Billed' : 'Sell')),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              _what,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                amount,
                key: const Key('sell-amount'),
                style: AppTypography.amount(
                  size: 44,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sell-note'),
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for (optional)',
              ),
            ),
            const SizedBox(height: 20),
            _Keypad(onPress: _press),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: _PayBar(
          what: _what,
          amount: amount,
          onPay: _minor > 0 ? _pay : null,
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onPress});

  final ValueChanged<String> onPress;

  static const _keys = [
    '1', '2', '3', //
    '4', '5', '6',
    '7', '8', '9',
    '00', '0', '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final key in _keys)
          Material(
            color: colors.border.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: Key('sell-key-$key'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => onPress(key),
              child: Center(
                child: key == '⌫'
                    ? Icon(
                        Icons.backspace_outlined,
                        semanticLabel: 'Delete',
                        color: theme.colorScheme.onSurface,
                      )
                    : Text(
                        key,
                        style: AppTypography.amount(
                          size: 24,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The total where the tab bar was: the same pill, in the brand colour.
class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.what,
    required this.amount,
    required this.onPay,
  });

  final String what;
  final String amount;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onPay != null;
    final fg = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      key: const Key('sell-pay'),
      color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPay,
        child: SizedBox(
          height: PillNavigationBar.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        what,
                        style: textTheme.bodySmall!.copyWith(color: fg),
                      ),
                      Text(
                        amount,
                        style: AppTypography.amount(size: 22, color: fg),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Pay',
                  style: textTheme.titleMedium!.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
