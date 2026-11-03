import '../enums.dart';
import 'payee_identifier.dart';

/// A named payee and the raw identifiers that resolve to it.
class PayeeRule {
  const PayeeRule({
    required this.id,
    required this.displayName,
    this.identifiers = const [],
    this.defaultCategoryId,
    this.leakType = LeakType.none,
    this.askPurpose = false,
  });

  final int id;
  final String displayName;
  final List<PayeeIdentifier> identifiers;
  final int? defaultCategoryId;
  final LeakType leakType;

  /// Money from them asks what it was for instead of taking a category.
  final bool askPurpose;
}

/// What a transaction shows once its payee and override are applied.
class AppliedPayee {
  const AppliedPayee({
    this.payeeId,
    this.displayName,
    this.categoryId,
    this.leakType = LeakType.none,
    this.isCategoryOverridden = false,
    this.isCategoryAuto = false,
    this.needsPurpose = false,
  });

  final int? payeeId;
  final String? displayName;

  /// Null means Uncategorised.
  final int? categoryId;
  final LeakType leakType;
  final bool isCategoryOverridden;
  final bool isCategoryAuto;

  /// Money in from a payee whose money has meant different things, not yet
  /// answered: it has no category until the person says what it was.
  final bool needsPurpose;
}

/// Applies [payee] to one transaction.
///
/// A category override on the transaction beats the payee's default
/// category, which beats an automatically suggested category. The override
/// touches the category only: the payee's display name and leak type still
/// apply, because the leak type describes who the money went to, not what it
/// was for.
///
/// Money in from a payee who [PayeeRule.askPurpose] takes neither their
/// category nor a suggestion: it waits for the person's answer.
AppliedPayee applyPayee(
  PayeeRule? payee, {
  int? categoryOverrideId,
  int? autoCategoryId,
  bool isInflow = false,
}) {
  final hasOverride = categoryOverrideId != null;
  final needsPurpose = !hasOverride && isInflow && (payee?.askPurpose ?? false);
  final hasPayeeDefault =
      !hasOverride && !needsPurpose && payee?.defaultCategoryId != null;
  final hasAuto =
      !hasOverride &&
      !needsPurpose &&
      !hasPayeeDefault &&
      autoCategoryId != null;
  return AppliedPayee(
    payeeId: payee?.id,
    displayName: payee?.displayName,
    categoryId: hasOverride
        ? categoryOverrideId
        : hasPayeeDefault
        ? payee!.defaultCategoryId
        : hasAuto
        ? autoCategoryId
        : null,
    leakType: payee?.leakType ?? LeakType.none,
    isCategoryOverridden: hasOverride,
    isCategoryAuto: hasAuto,
    needsPurpose: needsPurpose,
  );
}

/// Whether choosing [chosenId] for money in from [payee] shows their money
/// has meant different things: it differs from the payee's category or
/// from what earlier money from them was set to ([earlierIds]).
bool isMixedSender({
  required int chosenId,
  required int? payeeCategoryId,
  required Iterable<int> earlierIds,
}) =>
    (payeeCategoryId != null && payeeCategoryId != chosenId) ||
    earlierIds.any((id) => id != chosenId);

/// Resolves raw identifiers to payees.
class PayeeDirectory {
  PayeeDirectory(Iterable<PayeeRule> payees) : _payees = payees.toList();

  final List<PayeeRule> _payees;

  /// The payee for [identifier], or null when none or more than one could
  /// be it.
  ///
  /// An exact identifier wins. Otherwise masked numbers and whole-business
  /// paybills match, but only when every match points at the same payee, so
  /// a masked number never guesses between two people.
  PayeeRule? resolve(PayeeIdentifier identifier) {
    for (final payee in _payees) {
      if (payee.identifiers.contains(identifier)) return payee;
    }
    PayeeRule? found;
    for (final payee in _payees) {
      if (payee.identifiers.any(identifier.matches)) {
        if (found != null && found.id != payee.id) return null;
        found = payee;
      }
    }
    return found;
  }
}
