import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/security/application/balance_visibility.dart';

/// Masks every amount below it while balances are hidden.
class AmountsHidden extends InheritedWidget {
  const AmountsHidden({required this.hidden, required super.child, super.key});

  final bool hidden;

  /// Whether amounts are hidden here.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AmountsHidden>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(AmountsHidden oldWidget) =>
      hidden != oldWidget.hidden;
}

/// [text] with every amount in it, such as `KES 1,200`, masked while
/// amounts are hidden here.
String shownAmounts(BuildContext context, String text) =>
    maskAmountsIf(AmountsHidden.of(context), text);

/// The eye that shows or hides amounts, on a [color] background.
class AmountsEye extends ConsumerWidget {
  const AmountsEye({this.color, super.key});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancesHiddenProvider);
    return IconButton(
      key: const Key('amounts-eye'),
      tooltip: hidden ? 'Show balances' : 'Hide balances',
      color: color,
      visualDensity: VisualDensity.compact,
      icon: Icon(hidden ? Icons.visibility_off : Icons.visibility),
      onPressed: () => ref.read(balancesHiddenProvider.notifier).toggle(),
    );
  }
}
