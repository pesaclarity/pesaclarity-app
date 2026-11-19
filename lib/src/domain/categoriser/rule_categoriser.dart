import '../enums.dart';
import 'categoriser.dart';
import 'features.dart';

/// Confidence for a category the message type settles, such as airtime.
/// At [certainRuleConfidence] or more, the rules' answer is used even when
/// the model is loaded.
const kindRuleConfidence = 0.9;

/// Confidence for a well-known payee by name, such as Naivas or KPLC: as
/// certain as the message type, so it is used ahead of the model
/// ([certainRuleConfidence]).
const knownPayeeRuleConfidence = 0.9;

/// Confidence for a telling word in the payee's name, such as `mart` or
/// `hotel`: a guess, which the model makes instead when it is loaded.
const payeeRuleConfidence = 0.6;

/// Confidence for a guess from direction alone.
const weakRuleConfidence = 0.4;

/// One category's well-known payees (names of businesses and services) and
/// the words in a payee's name that suggest it.
typedef _PayeeRule = ({String key, List<String> payees, List<String> words});

/// Well-known Kenyan payees and words, by category key, for outflows. A
/// known payee anywhere in the table wins over a word; among each, the
/// first match wins, so specific entries come before general ones (a
/// matatu SACCO is transport, other SACCOs are savings).
const _outflowPayees = <_PayeeRule>[
  (
    key: 'transport',
    payees: ['uber', 'bolt', 'little cab', 'sgr'],
    words: ['matatu', 'fare'],
  ),
  (
    key: 'utilities',
    payees: ['kplc', 'zuku', 'faiba', 'safaricom home'],
    words: ['tokens', 'water', 'internet'],
  ),
  (
    key: 'fuel',
    payees: ['shell', 'rubis', 'totalenergies', 'ola'],
    words: ['petrol', 'fuel'],
  ),
  (
    key: 'groceries',
    payees: [
      'naivas',
      'quickmart',
      'carrefour',
      'chandarana',
      'magunas',
      'cleanshelf',
    ],
    words: ['supermarket', 'grocers', 'mart', 'butchery', 'mama mboga'],
  ),
  (
    key: 'eating_out',
    payees: ['kfc', 'java', 'artcaffe'],
    words: ['hotel', 'cafe', 'restaurant', 'kibanda', 'grill', 'pizza'],
  ),
  (
    key: 'snacks',
    payees: [],
    words: ['snacks', 'snack', 'bakery', 'bakers', 'ice cream', 'sweets'],
  ),
  (
    key: 'lifestyle',
    payees: ['showmax', 'netflix'],
    words: ['lounge', 'bar', 'club', 'cinema'],
  ),
  (key: 'airtime_data', payees: [], words: ['airtime', 'bundles', 'data']),
  (key: 'rent', payees: [], words: ['rent', 'landlord', 'apartments']),
  (
    key: 'school_fees',
    payees: [],
    words: ['school', 'academy', 'college', 'university', 'fees'],
  ),
  (
    key: 'health',
    payees: ['nhif', 'sha'],
    words: [
      'hospital',
      'clinic',
      'pharmacy',
      'chemist',
      'medical',
      'insurance',
    ],
  ),
  (
    key: 'betting',
    payees: ['sportpesa', 'betika', 'odibets', 'mozzart', 'betway'],
    words: ['bet'],
  ),
  (
    key: 'shopping',
    payees: ['jumia', 'kilimall'],
    words: ['boutique', 'shoes', 'hardware'],
  ),
  (
    key: 'giving',
    payees: [],
    words: ['church', 'tithe', 'harambee', 'parish', 'mosque'],
  ),
  (key: 'tax', payees: ['kra', 'itax'], words: []),
  (
    key: 'savings',
    payees: ['mshwari', 'ziidi'],
    words: ['sacco', 'mmf', 'money market'],
  ),
  (key: 'fuliza_repayment', payees: ['fuliza'], words: []),
  (key: 'loan_repayment', payees: ['tala', 'zenka'], words: ['loan']),
  (key: 'fees_charges', payees: [], words: ['charges', 'charge', 'fee']),
];

const _inflowPayees = <_PayeeRule>[
  (key: 'salary', payees: [], words: ['salary', 'payroll', 'wages']),
  (
    key: 'allowance_bursary',
    payees: ['helb'],
    words: ['allowance', 'bursary', 'stipend', 'scholarship'],
  ),
];

/// Built-in payee defaults and simple rules on the message type and payee
/// words: the whole categoriser when the model is refused, and, at
/// [certainRuleConfidence], ahead of it ([RulesFirstCategoriser]).
class RuleCategoriser implements Categoriser {
  const RuleCategoriser();

  @override
  SuggestionSource get source => SuggestionSource.rules;

  @override
  List<CategoryScore> score(CategoriserInput input) {
    final byKind = _byKind(input);
    if (byKind != null) return [CategoryScore(byKind, kindRuleConfidence)];

    final tokens = tokenise(input.payee);
    bool named(String phrase) => _containsPhrase(tokens, phrase.split(' '));
    final table = input.isInflow ? _inflowPayees : _outflowPayees;
    for (final rule in table) {
      if (rule.payees.any(named)) {
        return [CategoryScore(rule.key, knownPayeeRuleConfidence)];
      }
    }
    for (final rule in table) {
      if (rule.words.any(named)) {
        return [CategoryScore(rule.key, payeeRuleConfidence)];
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
