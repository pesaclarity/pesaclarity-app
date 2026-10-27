import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/statements/data/page_words.dart';

// Boxes are PDF coordinates: origin bottom-left, y up.
(double, double, double, double) _box(double left, double baseline) =>
    (left, baseline + 10, left + 5, baseline);

List<(double, double, double, double)> _run(
  double left,
  double baseline,
  int n,
) => [for (var i = 0; i < n; i++) _box(left + i * 5, baseline)];

void main() {
  test('splits words at spaces, gaps and lines, and flips y', () {
    final page = pageFromCharacters('Paid In1,500.00\nTJA', [
      ..._run(100, 700, 4), // Paid
      (0, 0, 0, 0), // space with no box
      ..._run(125, 700, 2), // In
      // No space before the amount, but a wide gap: still two words.
      ..._run(200, 700, 8),
      (0, 0, 0, 0), // newline
      ..._run(30, 680, 3), // next line
    ], pageHeight: 800);
    expect(page.words.map((w) => w.text), ['Paid', 'In', '1,500.00', 'TJA']);
    final paid = page.words.first;
    expect(paid.left, 100);
    expect(paid.right, 120);
    expect(paid.top, 90);
    expect(paid.bottom, 100);
    expect(page.words.last.top, 110);
    expect(page.text, 'Paid In 1,500.00\nTJA');
  });

  test('narrow characters and marks stay inside their word', () {
    // "1-0" with ink boxes: a thin 1, a short hyphen above the baseline.
    final page = pageFromCharacters('1-0,', [
      (30, 710, 31.8, 700),
      (33.4, 705.5, 35.1, 704.9),
      (36.6, 710, 40, 700),
      (40.8, 701, 41.5, 698.3),
    ], pageHeight: 800);
    expect(page.words.single.text, '1-0,');
  });

  test('a sign stays on the number after it', () {
    // A hyphen's box is far shorter than the gap to the digit after it.
    final page = pageFromCharacters('-15.00', [
      (500, 705.5, 501.7, 704.9),
      ..._run(503.5, 700, 5),
    ], pageHeight: 800);
    expect(page.words.single.text, '-15.00');
  });

  test('a word that moves to another line without a break splits', () {
    final page = pageFromCharacters('ABCD', [
      ..._run(30, 700, 2),
      ..._run(40, 650, 2),
    ], pageHeight: 800);
    expect(page.words.map((w) => w.text), ['AB', 'CD']);
  });

  test('more characters than boxes reads what it can', () {
    final page = pageFromCharacters('ABC', _run(30, 700, 2), pageHeight: 800);
    expect(page.words.single.text, 'AB');
  });
}
