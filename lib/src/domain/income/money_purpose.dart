/// What money in from a person was for, as "What was this?" asks it.
enum MoneyPurpose {
  familySupport('Family support', 'support_received'),
  work('Payment for work', 'business_income'),
  loanToYou('A loan to you', 'loan_repayment', hint: 'Added to Debts'),
  payingBack(
    'Paying you back',
    'own_transfer',
    hint: 'Lowers what they owe you',
  ),
  gift('A gift', 'gifts_received'),
  sale('A sale', 'business_income', hint: 'For your business');

  const MoneyPurpose(this.label, this.categoryKey, {this.hint});

  final String label;

  /// The seeded category the answer files the money under.
  final String categoryKey;
  final String? hint;
}
