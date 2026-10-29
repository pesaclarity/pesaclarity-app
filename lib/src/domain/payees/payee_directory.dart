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
  });

  final int id;
  final String displayName;
  final List<PayeeIdentifier> identifiers;
  final int? defaultCategoryId;
  final LeakType leakType;
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
  });

  final int? payeeId;
  final String? displayName;

  /// Null means Uncategorised.
  final int? categoryId;
  final LeakType leakType;
  final bool isCategoryOverridden;
  final bool isCategoryAuto;
}

/// Applies [payee] to one transaction.
///
/// A category override on the transaction beats the payee's default
/// category, which beats an automatically suggested category. The override
/// touches the category only: the payee's display name and leak type still
/// apply, because the leak type describes who the money went to, not what it
/// was for.
AppliedPayee applyPayee(
  PayeeRule? payee, {
  int? categoryOverrideId,
  int? autoCategoryId,
}) {
  final hasOverride = categoryOverrideId != null;
  final hasPayeeDefault = !hasOverride && payee?.defaultCategoryId != null;
  final hasAuto = !hasOverride && !hasPayeeDefault && autoCategoryId != null;
  return AppliedPayee(
    payeeId: payee?.id,
    displayName: payee?.displayName,
    categoryId: categoryOverrideId ?? payee?.defaultCategoryId ?? autoCategoryId,
    leakType: payee?.leakType ?? LeakType.none,
    isCategoryOverridden: hasOverride,
    isCategoryAuto: hasAuto,
  );
}

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
