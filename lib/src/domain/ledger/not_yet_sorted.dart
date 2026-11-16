import '../../core/money/money.dart';
import '../time/calendar.dart';
import 'ledger_entry.dart';
import 'ledger_role.dart';

/// A message waiting to be checked, as far as the reader could read it.
typedef MessageToCheck = ({int? amountMinor, String? currency});

/// Money the app has seen but cannot place yet, for Home's "not yet sorted"
/// card.
///
/// Two things count: money in from people not named yet (their amounts are
/// known) and messages waiting to be checked (their amount counts only when
/// the reader reads one). Balance gaps are left out on purpose: they have
/// their own warning on Home, `BalanceWarningLine`.
class NotYetSorted {
  const NotYetSorted({
    this.amountMinor = 0,
    this.messagesToCheck = 0,
    this.peopleNotNamed = 0,
    this.firstNotNamed,
  });

  /// Sums [entries] waiting for a payee name and [messages] waiting to be
  /// checked.
  ///
  /// Only amounts in the base currency are added. The ledger already turns
  /// other currencies into it where a rate is known, so what is left out is
  /// money with no rate yet, and messages in another currency; both are
  /// still counted.
  factory NotYetSorted.of(
    Iterable<LedgerEntry> entries,
    Iterable<MessageToCheck> messages,
  ) {
    var amount = 0;
    var messageCount = 0;
    final people = <String>{};
    CalendarDate? first;
    for (final e in entries) {
      if (roleOf(e) != LedgerRole.awaitingPayee) continue;
      people.add(_personKey(e));
      if (e.currency == BaseCurrency.code) amount += e.amountMinor;
      if (first == null || e.date.isBefore(first)) first = e.date;
    }
    for (final m in messages) {
      messageCount++;
      final minor = m.amountMinor;
      if (minor != null &&
          minor > 0 &&
          (m.currency ?? BaseCurrency.code) == BaseCurrency.code) {
        amount += minor;
      }
    }
    return NotYetSorted(
      amountMinor: amount,
      messagesToCheck: messageCount,
      peopleNotNamed: people.length,
      firstNotNamed: first,
    );
  }

  /// Known amounts in the base currency; 0 when none is known.
  final int amountMinor;
  final int messagesToCheck;

  /// Distinct people whose money in waits for a name.
  final int peopleNotNamed;

  /// The day of the oldest payment from someone not named yet.
  final CalendarDate? firstNotNamed;

  bool get isEmpty => messagesToCheck == 0 && peopleNotNamed == 0;

  bool get hasAmount => amountMinor > 0;

  /// The parts that make it up, such as `3 messages to check` and
  /// `1 person not named`; a part that is zero is left out.
  List<String> get parts => [
    if (messagesToCheck == 1) '1 message to check',
    if (messagesToCheck > 1) '$messagesToCheck messages to check',
    if (peopleNotNamed == 1) '1 person not named',
    if (peopleNotNamed > 1) '$peopleNotNamed people not named',
  ];
}

/// One person, however many times they sent money: their number or till
/// when the message gave one, else the name it printed.
String _personKey(LedgerEntry e) {
  if (e.counterpartyKind != null && e.counterpartyValue != null) {
    return '${e.counterpartyKind!.name}:${e.counterpartyValue}';
  }
  final name = e.counterpartyName?.trim().toLowerCase();
  if (name != null && name.isNotEmpty) return 'name:$name';
  return 'entry:${e.id}';
}
