import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/adaptive/adaptive.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/app_fonts.dart';

/// A choice of two never breaks a word of its labels: side by side while
/// they fit, at the phone's text size or a little under it (no less than
/// three quarters of it), one above the other when they do not.
void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(
    WidgetTester tester,
    double scale, {
    double width = 320,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 800),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: AdaptiveSegmented<bool>(
                  showSelectedIcon: false,
                  segments: const [(true, 'Customers'), (false, 'Suppliers')],
                  selected: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void expectOneLine(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: label.length),
    );
    expect(boxes.map((b) => b.top).toSet(), hasLength(1), reason: label);
  }

  testWidgets('side by side at the usual text size', (tester) async {
    await pump(tester, 1);
    final a = tester.getRect(find.text('Customers'));
    final b = tester.getRect(find.text('Suppliers'));
    expect(a.center.dy, b.center.dy);
    expectOneLine(tester, 'Customers');
    expectOneLine(tester, 'Suppliers');
  });

  testWidgets('side by side at twice the text size on a common phone, a '
      'little smaller', (tester) async {
    await pump(tester, 2, width: 390);
    final a = tester.getRect(find.text('Customers'));
    final b = tester.getRect(find.text('Suppliers'));
    expect(a.center.dy, b.center.dy);
    expectOneLine(tester, 'Customers');
    expectOneLine(tester, 'Suppliers');
    final scale =
        tester
            .renderObject<RenderParagraph>(find.text('Customers'))
            .textScaler
            .scale(14) /
        14;
    expect(scale, lessThan(2));
    expect(scale, greaterThanOrEqualTo(1.5));
  });

  testWidgets('one above the other at twice the text size on a narrow '
      'phone', (tester) async {
    await pump(tester, 2);
    final a = tester.getRect(find.text('Customers'));
    final b = tester.getRect(find.text('Suppliers'));
    expect(b.top, greaterThan(a.bottom));
    expectOneLine(tester, 'Customers');
    expectOneLine(tester, 'Suppliers');
  });
}
