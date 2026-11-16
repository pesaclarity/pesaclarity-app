import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/ask/matcher.dart';
import 'package:pesaclarity/src/domain/ask/understanding.dart';

void main() {
  const food = AskEntity(SlotKind.category, 'c:1', 'Food');
  const transport = AskEntity(SlotKind.category, 'c:2', 'Transport');
  const groceries = AskEntity(SlotKind.category, 'c:3', 'Groceries');
  const johnK = AskEntity(SlotKind.payee, 'p:1', 'John Kamau');
  const johnO = AskEntity(SlotKind.payee, 'p:2', 'John Otieno');
  const naivas = AskEntity(SlotKind.payee, 'p:3', 'Naivas');
  const power = AskEntity(SlotKind.payee, 'p:4', 'Kenya Power');
  const cafe = AskEntity(SlotKind.payee, 'p:5', 'Café Java');
  const mpesa = AskEntity(SlotKind.account, 'a:1', 'M-Pesa');
  const tomatoes = AskEntity(SlotKind.item, 'i:1', 'Tomatoes');
  final all = [
    food,
    transport,
    groceries,
    johnK,
    johnO,
    naivas,
    power,
    cafe,
    mpesa,
    tomatoes,
  ];

  MatchResult match(
    String text,
    List<SlotKind> kinds, {
    List<AskShortcut> shortcuts = const [],
  }) => EntityMatcher(all, shortcuts: shortcuts).match(text, kinds);

  AskEntity? one(String text, [List<SlotKind>? kinds]) =>
      switch (match(text, kinds ?? SlotKind.values)) {
        Matched(:final entity) => entity,
        _ => null,
      };

  test('normalises case, accents and punctuation', () {
    expect(normaliseName('  Café-JAVA! '), 'cafe java');
    expect(one('cafe java'), cafe);
    expect(one('m pesa', [SlotKind.account]), mpesa);
  });

  test('exact and whole-word names', () {
    expect(one('food'), food);
    expect(one('kenya power'), power);
    expect(one('power', [SlotKind.payee]), power);
  });

  test('typos', () {
    expect(one('naivaz', [SlotKind.payee]), naivas);
    expect(one('tranport', [SlotKind.category]), transport);
    expect(one('tomatos', [SlotKind.item]), tomatoes);
    expect(editDistance('kitten', 'sitting'), 3);
  });

  test('Swahili and Sheng category words', () {
    expect(one('chakula', [SlotKind.category]), food);
    expect(one('fare', [SlotKind.category]), transport);
    expect(one('supermarkets', [SlotKind.category]), groceries);
  });

  test('two people of one name are asked about', () {
    final result = match('john', [SlotKind.payee]);
    expect(result, isA<Ambiguous>());
    expect((result as Ambiguous).candidates, containsAll([johnK, johnO]));
  });

  test('a shortcut answers the ambiguity', () {
    final result = match(
      'John',
      [SlotKind.payee],
      shortcuts: [const AskShortcut('john', SlotKind.payee, 'p:2')],
    );
    expect((result as Matched).entity, johnO);
  });

  test('kinds are tried in order', () {
    expect(one('naivas', [SlotKind.category, SlotKind.payee]), naivas);
  });

  test('unrelated words match nothing', () {
    expect(match('zebra', SlotKind.values), isA<NoMatch>());
    expect(match('', SlotKind.values), isA<NoMatch>());
  });
}
