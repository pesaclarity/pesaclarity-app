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
  // Food delivery by the ride apps, before the rides themselves.
  (key: 'eating_out', payees: ['uber eats', 'bolt food', 'glovo'], words: []),
  (
    key: 'transport',
    // Ride apps, rail, airlines and long-distance coaches; a matatu, taxi or
    // boda boda in the name is as certain. Fuel stations are fuel.
    payees: [
      'uber',
      'bolt',
      'little cab',
      'little ride',
      'faras',
      'sgr',
      'madaraka express',
      'kenya railways',
      'kenya airways',
      'jambojet',
      'safarilink',
      'easy coach',
      'easycoach',
      'modern coast',
      'matatu',
      'taxi',
      'boda',
    ],
    words: ['fare', 'fares', 'shuttle', 'travellers', 'cab', 'cabs', 'bus'],
  ),
  (
    key: 'utilities',
    payees: ['kplc', 'zuku', 'faiba', 'safaricom home'],
    words: ['tokens', 'water', 'internet'],
  ),
  (
    key: 'fuel',
    payees: [
      'shell',
      'rubis',
      'totalenergies',
      'total energies',
      'ola',
      'vivo energy',
      'astrol',
      'hass petroleum',
    ],
    words: ['petrol', 'fuel'],
  ),
  (
    key: 'groceries',
    payees: [
      'naivas',
      'quickmart',
      'quick mart',
      'carrefour',
      'khetias',
      'eastmatt',
      'mulleys',
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
  // Money in that names a salary or payroll is pay (a salary advance is a
  // loan, which [_salaryAdvance] keeps out).
  (
    key: 'salary',
    payees: ['salary', 'salaries', 'payroll', 'wages', 'net pay'],
    words: [],
  ),
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
    final advance = input.isInflow && _salaryAdvance.any(named);
    for (final rule in table) {
      if (advance && rule.key == 'salary') continue;
      if (rule.payees.any(named)) {
        return [CategoryScore(rule.key, knownPayeeRuleConfidence)];
      }
    }
    for (final rule in table) {
      if (advance && rule.key == 'salary') continue;
      if (rule.words.any(named)) {
        return [CategoryScore(rule.key, payeeRuleConfidence)];
      }
    }
    if (fromPerson(input)) {
      return const [CategoryScore('money_received', weakRuleConfidence)];
    }
    return const [];
  }

  String? _byKind(CategoriserInput input) => switch (input.kind) {
    TransactionKind.airtime when !input.isInflow => 'airtime_data',
    TransactionKind.fulizaRepayment => 'fuliza_repayment',
    TransactionKind.loanRepayment => 'loan_repayment',
    TransactionKind.charge when !input.isInflow => 'fees_charges',
    TransactionKind.roundUp => 'savings',
    _ => null,
  };

  @override
  void close() {}
}

const _salaryAdvance = ['advance', 'loan'];

/// The categories for money in from a person. Which one only the person
/// knows (a payment, family support or a gift), so the model chooses among
/// them ([RulesFirstCategoriser]), and without it the rules say
/// `money_received`.
const receivedFromPeopleKeys = [
  'money_received',
  'support_received',
  'gifts_received',
];

/// Statement wording for a transfer from a person or a phone.
const _transferFrom = [
  'customer transfer from',
  'funds received from',
  'received from',
];

/// Words that make a sender a business, not a person.
const _businessWords = {
  'ltd',
  'limited',
  'plc',
  'company',
  'co',
  'inc',
  'enterprises',
  'enterprise',
  'traders',
  'agencies',
  'agency',
  'services',
  'solutions',
  'consultants',
  'consulting',
  'investments',
  'holdings',
  'bank',
  'sacco',
  'fund',
  'trust',
  'foundation',
  'group',
  'chama',
  'county',
  'government',
  'university',
  'college',
  'school',
  'church',
  'insurance',
  'mpesa',
  'pesa',
  'safaricom',
  'airtel',
  'bulk',
  'b2c',
  'paybill',
  'till',
  'account',
  'acc',
  'reversal',
  'refund',
  'interest',
  'dividend',
};

/// Money in that came from a person: M-PESA's "received from" a name (or a
/// statement's transfer from a phone), with nothing in the name that makes
/// it a business. Rules on the payee's words come first, so a salary or a
/// bursary that names itself is not from a person.
bool fromPerson(CategoriserInput input) {
  if (!input.isInflow) return false;
  final tokens = tokenise(input.payee);
  bool named(String phrase) => _containsPhrase(tokens, phrase.split(' '));
  final statementTransfer =
      _transferFrom.any(named) ||
      (input.kind == TransactionKind.bank && tokens.contains(phoneToken));
  if (input.kind != TransactionKind.received && !statementTransfer) {
    return false;
  }
  if (_inflowPayees.any((r) => [...r.payees, ...r.words].any(named))) {
    return false;
  }
  final name = [
    for (final t in tokens)
      if (t != phoneToken &&
          t != numToken &&
          !const {
            'customer',
            'transfer',
            'funds',
            'received',
            'from',
          }.contains(t))
        t,
  ];
  if (name.isEmpty) return input.kind == TransactionKind.received;
  if (name.length > 4) return false;
  return !name.any(
    (t) => _businessWords.contains(t) || t.contains(RegExp('[0-9]')),
  );
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
