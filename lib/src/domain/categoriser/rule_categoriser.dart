import '../enums.dart';
import 'categoriser.dart';
import 'features.dart';

/// Confidence for a category the message type settles, such as airtime.
const kindRuleConfidence = 0.9;

/// Confidence for a well-known payee or a telling word in its name.
const payeeRuleConfidence = 0.6;

/// Confidence for a guess from direction alone.
const weakRuleConfidence = 0.4;

/// Well-known Kenyan payees and words, by category key, for outflows. The
/// first match wins, so specific entries come before general ones (a
/// matatu SACCO is transport, other SACCOs are savings).
const _outflowPayees = <(String, List<String>)>[
  ('transport', ['matatu', 'uber', 'bolt', 'little cab', 'sgr', 'fare']),
  (
    'utilities',
    ['kplc', 'tokens', 'water', 'zuku', 'faiba', 'safaricom home', 'internet'],
  ),
  ('fuel', ['petrol', 'shell', 'rubis', 'totalenergies', 'fuel', 'ola']),
  (
    'groceries',
    [
      'naivas',
      'quickmart',
      'carrefour',
      'chandarana',
      'magunas',
      'cleanshelf',
      'supermarket',
      'grocers',
      'mart',
      'butchery',
      'mama mboga',
    ],
  ),
  (
    'eating_out',
    [
      'hotel',
      'cafe',
      'restaurant',
      'kibanda',
      'grill',
      'kfc',
      'java',
      'artcaffe',
      'pizza',
    ],
  ),
  ('snacks', ['snacks', 'snack', 'bakery', 'bakers', 'ice cream', 'sweets']),
  ('lifestyle', ['lounge', 'bar', 'club', 'cinema', 'showmax', 'netflix']),
  ('airtime_data', ['airtime', 'bundles', 'data']),
  ('rent', ['rent', 'landlord', 'apartments']),
  ('school_fees', ['school', 'academy', 'college', 'university', 'fees']),
  (
    'health',
    [
      'hospital',
      'clinic',
      'pharmacy',
      'chemist',
      'nhif',
      'sha',
      'medical',
      'insurance',
    ],
  ),
  ('betting', ['sportpesa', 'betika', 'odibets', 'mozzart', 'betway', 'bet']),
  ('shopping', ['jumia', 'kilimall', 'boutique', 'shoes', 'hardware']),
  ('giving', ['church', 'tithe', 'harambee', 'parish', 'mosque']),
  ('tax', ['kra', 'itax']),
  ('savings', ['sacco', 'mshwari', 'mmf', 'money market', 'ziidi']),
  ('fuliza_repayment', ['fuliza']),
  ('loan_repayment', ['loan', 'tala', 'zenka']),
  ('fees_charges', ['charges', 'charge', 'fee']),
];

const _inflowPayees = <(String, List<String>)>[
  ('salary', ['salary', 'payroll', 'wages']),
];

/// The fallback when no model is installed: built-in payee defaults and
/// simple rules on the message type and payee words.
class RuleCategoriser implements Categoriser {
  const RuleCategoriser();

  @override
  SuggestionSource get source => SuggestionSource.rules;

  @override
  List<CategoryScore> score(CategoriserInput input) {
    final byKind = _byKind(input);
    if (byKind != null) return [CategoryScore(byKind, kindRuleConfidence)];

    final tokens = tokenise(input.payee);
    for (final (key, words)
        in input.isInflow ? _inflowPayees : _outflowPayees) {
      if (words.any((w) => _containsPhrase(tokens, w.split(' ')))) {
        return [CategoryScore(key, payeeRuleConfidence)];
      }
    }
    if (input.isInflow && input.kind == TransactionKind.received) {
      return const [CategoryScore('money_received', weakRuleConfidence)];
    }
    return const [];
  }

  String? _byKind(CategoriserInput input) => switch (input.kind) {
    TransactionKind.airtime when !input.isInflow => 'airtime_data',
    TransactionKind.fulizaRepayment => 'fuliza_repayment',
    TransactionKind.charge when !input.isInflow => 'fees_charges',
    TransactionKind.roundUp => 'savings',
    _ => null,
  };

  @override
  void close() {}
}

bool _containsPhrase(List<String> tokens, List<String> phrase) {
  for (var i = 0; i + phrase.length <= tokens.length; i++) {
    var match = true;
    for (var j = 0; j < phrase.length && match; j++) {
      match = tokens[i + j] == phrase[j];
    }
    if (match) return true;
  }
  return false;
}
