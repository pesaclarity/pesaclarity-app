import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../../features/security/application/balance_visibility.dart';

/// Hiding amounts, the same way on every screen.
///
/// One switch, the eye, hides amounts across the app; it starts from the
/// "Hide balances on open" setting. Hidden: every amount on the tabs and the
/// screens opened from them. Shown: the counter (Sell, Pay, tabs, Close the
/// day, the record sheets), forms where an amount is typed, and receipts,
/// invoices and statements chosen to share or print.
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

/// Puts the eye's state over the whole app, so every screen and sheet
/// follows it.
class AmountsHiddenScope extends ConsumerWidget {
  const AmountsHiddenScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      AmountsHidden(hidden: ref.watch(balancesHiddenProvider), child: child);
}

/// [minor] as money, or dots when [hidden]. One look for every amount on
/// a screen: a plain `1,200` in the base currency, and `USD 25.00` in any
/// other. Pass [withCurrency] true for the figure a red card leads with,
/// the one place the base currency's code shows, or false for never.
String moneyOrHidden(
  int minor, {
  required bool hidden,
  String? currency,
  bool? withCurrency,
}) {
  final money = currency == null
      ? Money(minor)
      : Money(minor, currency: currency);
  final code = withCurrency ?? money.currency != BaseCurrency.code;
  if (!hidden) return formatMoney(money, withCurrency: code);
  return code ? '${money.currency} $maskedDigits' : maskedDigits;
}

/// [minor] as money, or dots while amounts are hidden here. See
/// [moneyOrHidden] for when the currency code shows.
String shownMoney(
  BuildContext context,
  int minor, {
  String? currency,
  bool? withCurrency,
}) => moneyOrHidden(
  minor,
  hidden: AmountsHidden.of(context),
  currency: currency,
  withCurrency: withCurrency,
);

/// [text] with every amount in it, such as `KES 1,200`, masked while
/// amounts are hidden here.
String shownAmounts(BuildContext context, String text) =>
    maskAmountsIf(AmountsHidden.of(context), text);

/// The eye that shows or hides amounts. It is the same everywhere: at the
/// right of a screen's title, or on the red card a screen leads with (pass
/// that card's [color]). An open eye while amounts show, a slashed one
/// while they are hidden.
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
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: () => ref.read(balancesHiddenProvider.notifier).toggle(),
    );
  }
}
