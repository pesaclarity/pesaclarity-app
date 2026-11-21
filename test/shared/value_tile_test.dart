import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/beside_or_under.dart';
import 'package:pesaclarity/src/shared/widgets/value_tile.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/app_fonts.dart';
import '../helpers/whole_words.dart';

/// A row's value or button sits beside its title while the title keeps
/// whole words, and moves under it at large text. At the usual size a
/// [ValueTile] lays out exactly as a [ListTile]. Made-up names only.
void main() {
  setUpAll(loadAppFonts);

  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1}) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Card(child: child)),
      ),
    );
  }

  List<String> broken(WidgetTester tester) => [
    for (final text in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    ))
      ...brokenWords(text),
  ];

  Widget amount() => const Text('12,450');

  for (final subtitle in [null, 'Due 6 Nov · since 30 Oct']) {
    testWidgets('lays out as a ListTile at the usual size '
        '(${subtitle == null ? 'one' : 'two'} lines)', (tester) async {
      Widget? sub() => subtitle == null ? null : Text(subtitle);
      await pump(
        tester,
        ListTile(
          title: const Text('Wanjiku Atieno'),
          subtitle: sub(),
          trailing: amount(),
        ),
      );
      Rect rect(String text) => tester.getRect(find.text(text));
      final expected = {
        for (final t in ['Wanjiku Atieno', '12,450', ?subtitle]) t: rect(t),
      };
      final height = tester.getSize(find.byType(ListTile)).height;
      await pump(
        tester,
        ValueTile(
          title: const Text('Wanjiku Atieno'),
          subtitle: sub(),
          trailing: amount(),
        ),
      );
      for (final MapEntry(:key, :value) in expected.entries) {
        expect(rect(key), value, reason: key);
      }
      expect(tester.getSize(find.byType(ValueTile)).height, height);
    });
  }

  testWidgets('moves the value under the title at large text', (tester) async {
    const title = 'Wanjiku Atieno Kamaundu';
    await pump(
      tester,
      ValueTile(
        title: const Text(title),
        subtitle: const Text('Over 2 weeks · since 19 Oct'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            amount(),
            const SizedBox(width: 10),
            FilledButton(onPressed: () {}, child: const Text('Remind')),
          ],
        ),
      ),
      scale: 2,
    );
    expect(broken(tester), isEmpty);
    expect(
      tester.getTopLeft(find.text('12,450')).dy,
      greaterThan(tester.getBottomLeft(find.text(title)).dy),
    );
    await tester.tap(find.text('Remind'));
  });

  testWidgets('BesideOrUnder keeps the lead whole at large text', (
    tester,
  ) async {
    Widget row() => const BesideOrUnder(
      gap: 12,
      lead: Text('Mwangaza Wholesalers'),
      end: Text('1,250.00'),
    );
    await pump(tester, row());
    final beside = tester.getCenter(find.text('1,250.00')).dy;
    expect(
      beside,
      closeTo(tester.getCenter(find.text('Mwangaza Wholesalers')).dy, 0.5),
    );

    await pump(tester, SizedBox(width: 200, child: row()), scale: 2);
    expect(broken(tester), isEmpty);
    expect(
      tester.getTopLeft(find.text('1,250.00')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.text('Mwangaza Wholesalers')).dy,
      ),
    );
  });

  testWidgets('brokenWords finds a word split across lines', (tester) async {
    await pump(
      tester,
      const SizedBox(width: 60, child: Text('Mwangaza')),
      scale: 2,
    );
    expect(broken(tester), ['Mwangaza']);
  });
}
