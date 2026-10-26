import 'package:flutter/material.dart';

import '../../../theme/pesa_colors.dart';
import '../domain/pin_hasher.dart';

/// A PIN prompt: title, filled dots and a number pad.
///
/// Calls [onCompleted] once [pinLength] digits are in, then clears the dots.
class PinPad extends StatefulWidget {
  const PinPad({
    required this.title,
    required this.onCompleted,
    this.message,
    this.messageIsError = false,
    this.enabled = true,
    this.extraKey,
    this.footer,
    super.key,
  });

  final String title;
  final String? message;
  final bool messageIsError;

  /// False while a wait after wrong PINs runs.
  final bool enabled;

  /// Shown in the bottom-left gap of the pad, such as the fingerprint button.
  final Widget? extraKey;

  final Widget? footer;

  final Future<void> Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';
  bool _checking = false;

  bool get _active => widget.enabled && !_checking;

  Future<void> _add(String digit) async {
    if (!_active || _digits.length >= pinLength) return;
    setState(() => _digits += digit);
    if (_digits.length < pinLength) return;
    setState(() => _checking = true);
    try {
      await widget.onCompleted(_digits);
    } finally {
      if (mounted) {
        setState(() {
          _digits = '';
          _checking = false;
        });
      }
    }
  }

  void _delete() {
    if (!_active || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = PesaColors.of(context);
    final message = widget.message;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Semantics(
          label: '${_digits.length} of $pinLength digits entered',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pinLength; i++)
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _digits.length ? scheme.primary : null,
                    border: Border.all(color: scheme.primary, width: 1.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: _checking
              ? const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : message == null
              ? null
              : Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: widget.messageIsError
                        ? scheme.error
                        : colors.textMuted,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) _DigitKey(d, _active ? _add : null),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: _DigitKey.size,
              child: widget.extraKey == null
                  ? null
                  : Center(child: widget.extraKey),
            ),
            _DigitKey('0', _active ? _add : null),
            SizedBox.square(
              dimension: _DigitKey.size,
              child: Center(
                child: IconButton(
                  tooltip: 'Delete',
                  onPressed: _active && _digits.isNotEmpty ? _delete : null,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
            ),
          ],
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: 16),
          widget.footer!,
        ],
      ],
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey(this.digit, this.onTap);

  static const size = 76.0;

  final String digit;
  final void Function(String digit)? onTap;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: SizedBox.square(
        dimension: size - 12,
        child: TextButton(
          style: TextButton.styleFrom(
            shape: const CircleBorder(),
            textStyle: Theme.of(context).textTheme.headlineSmall,
          ),
          onPressed: tap == null ? null : () => tap(digit),
          child: Text(digit),
        ),
      ),
    );
  }
}
