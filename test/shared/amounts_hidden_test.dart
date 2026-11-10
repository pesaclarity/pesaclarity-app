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
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: DetailLine('Groceries and household supplies', 'M-Pesa'),
          ),
        ),
      ),
    );
    final tail = tester.renderObject<RenderParagraph>(find.text(' · M-Pesa'));
    expect(tail.didExceedMaxLines, isFalse);
    expect(tester.getSize(find.text(' · M-Pesa')).height, lessThan(30));
    // With a little more room, the category takes two lines rather than
    // cutting short, and the account sits on the last of them.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: DetailLine('Groceries and household supplies', 'M-Pesa'),
          ),
        ),
      ),
    );
    final lead = find.text('Groceries and household supplies');
    expect(
      tester.renderObject<RenderParagraph>(lead).didExceedMaxLines,
      isFalse,
    );
    expect(tester.getSize(lead).height, greaterThan(30));
    expect(
      tester.getBottomLeft(find.text(' · M-Pesa')).dy,
      tester.getBottomLeft(lead).dy,
    );
    final line = tester.widget<DetailLine>(find.byType(DetailLine));
    expect(
      '${line.lead} · ${line.tail}',
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
