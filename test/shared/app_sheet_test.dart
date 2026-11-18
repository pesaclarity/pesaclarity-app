import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';
import 'package:pesaclarity/src/shared/widgets/selector_field.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext context) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet closes with its close button', (tester) async {
    await open(
      tester,
      (context) => showAppSheet<void>(
        context: context,
        builder: (context) =>
            const SheetBody(title: 'Add a goal', children: [Text('Body')]),
      ),
    );
    expect(find.text('Add a goal'), findsOneWidget);

    // The close button sits at the start of the handle's row, above the
    // title, and is a full tap target.
    final close = find.byTooltip('Close');
    expect(
      tester.getRect(close).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Add a goal')).top),
    );
    expect(tester.getSize(close).height, greaterThanOrEqualTo(44));

    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Add a goal'), findsNothing);
  });

  testWidgets('an option sheet closes with its close button', (tester) async {
    String? picked = 'unset';
    await open(tester, (context) async {
      picked = await showOptionSheet<String>(
        context,
        title: 'Account',
        options: const [('a', 'M-Pesa'), ('b', 'Cash')],
        selected: 'a',
      );
    });
    expect(find.text('Cash'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Cash'), findsNothing);
    expect(picked, isNull);
  });
}
