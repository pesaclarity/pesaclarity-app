import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether amounts are masked on screen right now.
///
/// Starts from the "Hide balances on open" setting each time the app opens
/// or unlocks; the eye button flips it until then.
class BalancesHidden extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool hidden) => state = hidden;

  void toggle() => state = !state;
}

final balancesHiddenProvider = NotifierProvider<BalancesHidden, bool>(
  BalancesHidden.new,
);

/// Shown in place of the digits of a hidden amount.
const maskedDigits = '•••••';

final _amount = RegExp(r'-?\b([A-Z]{3}) \d+(?:,\d{3})*(?:\.\d+)?');

/// Whether [text] contains an amount such as `KES 1,200`.
bool containsAmount(String text) => _amount.hasMatch(text);

/// Replaces every amount in [text], such as `KES 1,200.50`, with `KES •••••`.
String maskAmounts(String text) =>
    text.replaceAllMapped(_amount, (m) => '${m[1]} $maskedDigits');

/// [text] with amounts masked when [hidden].
String maskAmountsIf(bool hidden, String text) =>
    hidden ? maskAmounts(text) : text;
