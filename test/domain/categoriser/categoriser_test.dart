import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/categoriser/categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/features.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/domain/categoriser/suggester.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

/// The manifest pesaclarity-ml writes for the shipping config.
Map<String, Object?> manifestJson({
  int version = 1,
  int maxTokens = 8,
  List<int>? shape,
  List<String>? layout,
}) => {
  'model_file': 'categoriser.tflite',
  'model_sha256': 'AB' * 32,
  'model_size_bytes': 81234,
  'feature_schema_version': version,
  'feature_config': {'max_tokens': maxTokens, 'hash_buckets': 4096},
  'input': {
    'name': 'features',
    'dtype': 'int32',
    'shape': shape ?? [-1, maxTokens + 5],
  },
  'layout': layout ?? FeatureConfig(maxTokens: maxTokens).layout,
};

class FakeRuntime implements TfliteRuntime {
  FakeRuntime(this.probs);

  final List<double> probs;
  final rows = <List<int>>[];
  var closed = false;

  @override
  int get outputSize => probs.length;

  @override
  List<double> run(List<int> row) {
    rows.add(row);
    return probs;
  }

  @override
  void close() => closed = true;
}

LedgerEntry entry({
  int id = 1,
  String? name,
  bool inflow = false,
  TransactionKind kind = TransactionKind.till,
  int? categoryId,
  PayeeIdentifierKind? idKind,
  String? idValue,
}) => LedgerEntry(
  id: id,
  accountId: 1,
  occurredAt: DateTime.utc(2026, 10, 27, 9),
  amountMinor: 144000,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: kind,
  categoryId: categoryId,
  counterpartyName: name,
  counterpartyKind: idKind,
  counterpartyValue: idValue,
);

const options = [
  CategoryOption(id: 1, key: 'groceries', type: CategoryType.expense),
  CategoryOption(id: 2, key: 'eating_out', type: CategoryType.expense),
  CategoryOption(id: 3, key: 'salary', type: CategoryType.income),
  CategoryOption(id: 4, key: 'money_received', type: CategoryType.income),
  CategoryOption(id: 9, type: CategoryType.expense),
];

class FixedCategoriser implements Categoriser {
  FixedCategoriser(this.scores);

  final List<CategoryScore> scores;

  @override
  SuggestionSource get source => SuggestionSource.model;

  @override
  List<CategoryScore> score(CategoriserInput input) => scores;

  @override
  void close() {}
}

void main() {
  group('model manifest', () {
    test('accepts the shipping manifest', () {
      final m = ModelManifest.fromJson(manifestJson());
      expect(m.incompatibilities(), isEmpty);
      expect(m.modelSha256, 'ab' * 32);
      expect(m.featureConfig, const FeatureConfig());
    });

    test('refuses a feature schema version it cannot feed', () {
      final m = ModelManifest.fromJson(manifestJson(version: 2));
      expect(m.incompatibilities().single, contains('schema version 2'));
    });

    test('refuses an input or layout that differs from the pipeline', () {
      expect(
        ModelManifest.fromJson(manifestJson(shape: [-1, 12]))
            .incompatibilities(),
        ['input shape [-1, 12]'],
      );
      expect(
        ModelManifest.fromJson(
          manifestJson(layout: const FeatureConfig().layout.reversed.toList()),
        ).incompatibilities(),
        ['feature layout differs'],
      );
    });

    test('reads another token count when the manifest says so', () {
      final m = ModelManifest.fromJson(manifestJson(maxTokens: 6));
      expect(m.incompatibilities(), isEmpty);
      expect(m.featureConfig.width, 11);
    });

    test('rejects malformed manifests and labels', () {
      expect(
        () => ModelManifest.fromJson({...manifestJson(), 'input': null}),
        throwsFormatException,
      );
      expect(
        () => ModelLabels.fromJson({
          'version': 1,
          'labels': ['a', 'a'],
        }),
        throwsFormatException,
      );
    });
  });

  group('TfliteCategoriser', () {
    final labels = ModelLabels.fromJson({
      'version': 1,
      'labels': ['groceries', 'eating_out', 'salary'],
    });

    test('encodes the row and ranks labels by probability', () {
      final runtime = FakeRuntime([0.1, 0.7, 0.2]);
      final c = TfliteCategoriser(
        manifest: ModelManifest.fromJson(manifestJson()),
        labels: labels,
        runtime: runtime,
      );
      // 2026-03-18 12:00 EAT, from case `till_basic`.
      final input = CategoriserInput(
        payee: 'DEMO FRESH MART TILL 000123',
        amountMinor: 120000,
        isInflow: false,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          1773824400000,
          isUtc: true,
        ),
      );
      final scores = c.score(input);
      expect(scores.map((s) => s.key), ['eating_out', 'salary', 'groceries']);
      // Case `till_basic` in feature_vectors.v1.json.
      expect(runtime.rows.single, [
        1465,
        2153,
        3589,
        3055,
        2358,
        0,
        0,
        0,
        5,
        0,
        3,
        2,
        1,
      ]);
    });

    test('refuses labels that do not match the outputs, closing it', () {
      final runtime = FakeRuntime([0.5, 0.5]);
      expect(
        () => TfliteCategoriser(
          manifest: ModelManifest.fromJson(manifestJson()),
          labels: labels,
          runtime: runtime,
        ),
        throwsA(isA<ModelRefused>()),
      );
      expect(runtime.closed, isTrue);
    });

    test('refuses a newer feature schema', () {
      expect(
        () => TfliteCategoriser(
          manifest: ModelManifest.fromJson(manifestJson(version: 2)),
          labels: labels,
          runtime: FakeRuntime([0, 0, 1]),
        ),
        throwsA(isA<ModelRefused>()),
      );
    });
  });

  group('RuleCategoriser', () {
    const rules = RuleCategoriser();
    List<String> keys(
      String payee, {
      bool inflow = false,
      TransactionKind? kind,
    }) => rules
        .score(
          CategoriserInput(
            payee: payee,
            amountMinor: 5000,
            isInflow: inflow,
            occurredAt: DateTime.utc(2026),
            kind: kind,
          ),
        )
        .map((s) => s.key)
        .toList();

    test('message type settles airtime, Fuliza and charges', () {
      expect(keys('', kind: TransactionKind.airtime), ['airtime_data']);
      expect(keys('', kind: TransactionKind.fulizaRepayment), [
        'fuliza_repayment',
      ]);
      expect(keys('', kind: TransactionKind.charge), ['fees_charges']);
    });

    test('well-known payees and words', () {
      expect(keys('Naivas Juja City'), ['groceries']);
      expect(keys('KPLC PREPAID'), ['utilities']);
      expect(keys('DEMO MATATU SACCO'), ['transport']);
      expect(keys('SAMPLE SACCO DEPOSIT'), ['savings']);
      expect(keys('DEMO SNACK KIOSK'), ['snacks']);
      expect(keys('SAMPLE BAKERY'), ['snacks']);
      expect(keys('DEMO KIBANDA CAFE'), ['eating_out']);
      expect(keys('FULIZA M-PESA'), ['fuliza_repayment']);
      expect(keys('SAMPLE MOBILE LOAN'), ['loan_repayment']);
      expect(keys('DEMO EMPLOYER LTD SALARY', inflow: true), ['salary']);
      expect(keys('John', inflow: true, kind: TransactionKind.received), [
        'money_received',
      ]);
      expect(keys('Unknown Business'), isEmpty);
    });
  });

  group('CategorySuggester', () {
    test("the person's choice for the payee wins over the model", () {
      final s = CategorySuggester(
        categoriser: FixedCategoriser([const CategoryScore('groceries', 0.9)]),
        categories: options,
        corrections: {'name:tamu tamu hotel': 9},
      );
      final suggestion = s.suggest(entry(name: 'TAMU TAMU Hotel'))!;
      expect(suggestion.categoryId, 9);
      expect(suggestion.source, SuggestionSource.correction);
      expect(suggestion.percent, 100);

      final other = s.suggest(entry(name: 'Naivas'))!;
      expect(other.categoryId, 1);
      expect(other.source, SuggestionSource.model);
      expect(other.percent, 90);
    });

    test('identifier keys come before name keys', () {
      final e = entry(
        name: 'John',
        idKind: PayeeIdentifierKind.phone,
        idValue: '0700***000',
      );
      expect(payeeKeys(e), ['id:phone:0700***000', 'name:john']);
      final s = CategorySuggester(
        categoriser: const RuleCategoriser(),
        categories: options,
        corrections: {'id:phone:0700***000': 2, 'name:john': 1},
      );
      expect(s.suggest(e)!.categoryId, 2);
    });

    test('skips labels that do not fit the direction or are missing', () {
      final s = CategorySuggester(
        categoriser: FixedCategoriser([
          const CategoryScore('salary', 0.6),
          const CategoryScore('rent', 0.3),
          const CategoryScore('eating_out', 0.31),
        ]),
        categories: options,
        corrections: const {},
      );
      final suggestion = s.suggest(entry(name: 'Demo'))!;
      expect(suggestion.key, 'eating_out');
      expect(suggestion.confidence, 0.31);
    });

    test('shows nothing below the confidence floor', () {
      final s = CategorySuggester(
        categoriser: FixedCategoriser([const CategoryScore('groceries', 0.2)]),
        categories: options,
        corrections: const {},
      );
      expect(s.suggest(entry(name: 'Demo')), isNull);
    });

    test('only lines that a category is for need one', () {
      expect(needsCategory(entry(name: 'Naivas')), isTrue);
      expect(needsCategory(entry(name: 'Naivas', categoryId: 1)), isFalse);
      expect(
        needsCategory(entry(kind: TransactionKind.fulizaDraw, inflow: true)),
        isFalse,
      );
      expect(
        needsCategory(entry(kind: TransactionKind.reversal, inflow: true)),
        isFalse,
      );
    });
  });
}
