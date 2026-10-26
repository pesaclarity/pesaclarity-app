/// What kind of statement some extracted PDF text is.
sealed class StatementType {
  const StatementType();
}

/// A Safaricom M-Pesa full statement, which the app can read.
final class MpesaStatementType extends StatementType {
  const MpesaStatementType();
}

/// A bank statement from [bankName], whose reader is still to come.
final class BankStatementType extends StatementType {
  const BankStatementType(this.bankName);

  final String bankName;
}

/// Text that matches no statement layout the app knows.
final class UnknownStatementType extends StatementType {
  const UnknownStatementType();
}

/// Works out which institution's statement [text] is from its header.
///
/// M-Pesa is recognised by its title or its table's column headings. Banks
/// are recognised by name near the top of the first page only, since
/// M-Pesa and bank names often appear in transaction details.
StatementType detectStatementType(String text) {
  final head = text.split(RegExp(r'\r\n|[\r\n\f]')).take(40).join('\n');
  if (_mpesaTitle.hasMatch(head) || _mpesaColumns.hasMatch(text)) {
    return const MpesaStatementType();
  }
  for (final (pattern, name) in _banks) {
    if (pattern.hasMatch(head)) return BankStatementType(name);
  }
  return const UnknownStatementType();
}

final _mpesaTitle = RegExp(r'^\s*M-?PESA\s+STATEMENT\b', multiLine: true);
final _mpesaColumns = RegExp(
  r'Receipt No\.?\s+Completion Time\s+Details',
  caseSensitive: false,
);

RegExp _bank(String pattern) => RegExp(pattern, caseSensitive: false);

final List<(RegExp, String)> _banks = [
  (_bank(r'\bKCB\b|Kenya Commercial Bank'), 'KCB'),
  (_bank(r'\bI\s?&\s?M\b'), 'I&M Bank'),
  (_bank(r'\bEquity\s+Bank\b'), 'Equity Bank'),
  (_bank(r'Co-?operative\s+Bank|\bCo-?op\s+Bank\b'), 'Co-operative Bank'),
  (_bank(r'\bNCBA\b'), 'NCBA'),
  (_bank(r'\bAbsa\b'), 'Absa'),
  (_bank(r'\bStanbic\b'), 'Stanbic'),
  (_bank(r'Standard\s+Chartered'), 'Standard Chartered'),
  (_bank(r'\bFamily\s+Bank\b'), 'Family Bank'),
  (_bank(r'Diamond\s+Trust|\bDTB\b'), 'DTB'),
  (_bank(r'\bBank\b.*\bStatement\b|\bStatement\b.*\bBank\b'), 'your bank'),
];
