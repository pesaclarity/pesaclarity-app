import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/shared/widgets/marks.dart';

void main() {
  test('money shows as dots while hidden, with or without the code', () {
    expect(moneyOrHidden(120000, hidden: false), '1,200');
    expect(
      moneyOrHidden(120000, hidden: false, withCurrency: true),
      'KES 1,200',
    );
    expect(moneyOrHidden(120000, hidden: true), '•••••');
    expect(
      moneyOrHidden(120000, hidden: true, withCurrency: true),
      'KES •••••',
    );
    expect(moneyOrHidden(5000, hidden: true, currency: 'USD'), 'USD •••••');
  });

  testWidgets('one eye: the same look on a red card and on a title row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AmountsHiddenScope(
            child: Scaffold(
              body: Column(
                children: [
                  HeroFigureCard(label: 'Sales today', figure: 'KES 4,850'),
                  Row(
                    children: [
                      Expanded(child: Text('Stock')),
                      AmountsEye(),
                    ],
                  ),
                  _Amount(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final eyes = find.byKey(const Key('amounts-eye'));
    expect(eyes, findsNWidgets(2));
    expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(2));
    expect(find.text('KES 4,850'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);

    // Either eye hides everything, and both then show the same slashed eye.
    await tester.tap(eyes.last);
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(2));
    expect(find.text('KES •••••'), findsOneWidget);
    expect(find.text('•••••'), findsOneWidget);
    expect(find.byTooltip('Show balances'), findsNWidgets(2));

    await tester.tap(eyes.first);
    await tester.pump();
    expect(find.text('KES 4,850'), findsOneWidget);
    expect(find.byTooltip('Hide balances'), findsNWidgets(2));
  });
  testWidgets('a long category wraps; the account always shows whole', (
    tester,
  ) async {
    Future<RenderParagraph> show(String lead, String tail, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(width: width, child: DetailLine(lead, tail)),
          ),
        ),
      );
      return tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(DetailLine),
          matching: find.byType(RichText),
        ),
      );
    }

    String said(RenderParagraph p) =>
        p.text.toPlainText().replaceAll(' ', ' ').replaceAll('⁠', '');

    // Room for all of it on two lines: nothing is cut.
    var line = await show('Groceries and household supplies', 'M-Pesa', 400);
    expect(said(line), 'Groceries and household supplies · M-Pesa');
    expect(line.didExceedMaxLines, isFalse);
    expect(line.size.height, greaterThan(30));

    // A short category with a long account flows as one sentence rather
    // than squeezing the category into a narrow column.
    line = await show('Salary', 'Equity Bank ···8765', 300);
    expect(said(line), 'Salary · Equity Bank ···8765');
    expect(line.didExceedMaxLines, isFalse);
    final first = line.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    expect(first, hasLength(1), reason: 'Salary stays on one line');

    // Too little room: the category shortens and the account stays whole.
    line = await show('Groceries and household supplies', 'M-Pesa', 220);
    expect(said(line), endsWith('… · M-Pesa'));
    expect(said(line), startsWith('Groceries'));
    expect(line.didExceedMaxLines, isFalse);

    final widget = tester.widget<DetailLine>(find.byType(DetailLine));
    expect(
      '${widget.lead} · ${widget.tail}',
      'Groceries and household supplies · M-Pesa',
    );
    expect(tester.takeException(), isNull);
  });
}

class _Amount extends StatelessWidget {
  const _Amount();

  @override
  Widget build(BuildContext context) =>
      Text(shownMoney(context, 120000, withCurrency: false));
}
