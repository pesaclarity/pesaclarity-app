import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/presentation/security_settings_card.dart';
import 'package:pesaclarity/src/shared/accessibility.dart';
import 'package:pesaclarity/src/shared/adaptive/adaptive.dart';
import 'package:pesaclarity/src/shared/widgets/choice_menu.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/layout.dart';

import '../helpers/app_fonts.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/whole_words.dart';
import '../screenshots/harness.dart'
    show accessibilityScales, phonePixelRatio, phoneSize;

/// A row with a drop-down at its end keeps every word whole at the text
/// sizes the accessibility check draws: the drop-down moves under the row's
/// title once a word would not fit beside it. At the usual size the row is
/// the ListTile it always was.
void main() {
  // The app's own fonts, so text takes the widths it takes on a phone.
  setUpAll(loadAppFonts);

  /// A [width] × 844 phone (390, as the accessibility check draws, unless
  /// given) at [scale] times the text size.
  void phone(WidgetTester tester, double scale, {double width = 390}) {
    tester.view
      ..physicalSize = width == 390
          ? phoneSize
          : Size(width * phonePixelRatio, phoneSize.height)
      ..devicePixelRatio = phonePixelRatio;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  /// [children] in cards on a screen, as Profile lays them out.
  Widget screen(List<Widget> children, {bool dark = false}) => MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    builder: (context, child) =>
        Theme(data: accessibleTheme(context, Theme.of(context)), child: child!),
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Layout.gutter,
          8,
          Layout.gutter,
          Layout.screenBottom,
        ),
        children: children,
      ),
    ),
  );

  /// Every word of every text under [of] is on one line.
  void expectWholeWords(WidgetTester tester, Finder of, String where) {
    for (final text in tester.renderObjectList<RenderParagraph>(
      find.descendant(of: of, matching: find.byType(RichText)),
    )) {
      expect(
        brokenWords(text),
        isEmpty,
        reason: '"${text.text.toPlainText()}" $where',
      );
    }
  }

  ChoiceMenu<String> menu(String choice) => ChoiceMenu<String>(
    key: const Key('menu'),
    options: [(choice, choice)],
    value: choice,
    onChanged: (_) {},
  );

  group('Lock after', () {
    /// Profile's Security card with a PIN set, so Lock after shows.
    Future<void> pumpSecurity(WidgetTester tester, {bool dark = false}) async {
      final store = MemorySecureStore();
      final vault = testKeyVault(store);
      // A made-up PIN.
      await vault.setPin('246810', await vault.readOrCreateOpenKey());
      await tester.pumpWidget(
        ProviderScope(
          overrides: appLockOverrides(store: store),
          child: screen(const [SecuritySettingsCard()], dark: dark),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lock after'), findsOneWidget);
    }

    for (final scale in accessibilityScales) {
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        testWidgets('keeps its words whole at ${scale}x text ($theme)', (
          tester,
        ) async {
          phone(tester, scale);
          await pumpSecurity(tester, dark: dark);
          expectWholeWords(
            tester,
            find.byType(SecuritySettingsCard),
            'at ${scale}x text ($theme)',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('keeps its menu beside it, at the end, at the usual size', (
      tester,
    ) async {
      phone(tester, 1);
      await pumpSecurity(tester);
      final title = tester.getRect(find.text('Lock after'));
      final pill = tester.getRect(find.byKey(const Key('lock-after')));
      final card = tester.getRect(find.byType(Card));
      expect(pill.center.dy, closeTo(title.center.dy, 0.5));
      expect(pill.right, card.right - 24);
    });

    testWidgets('moves its menu under it, at the end, at twice the size', (
      tester,
    ) async {
      phone(tester, 2);
      await pumpSecurity(tester);
      final title = tester.getRect(find.text('Lock after'));
      final pill = tester.getRect(find.byKey(const Key('lock-after')));
      final card = tester.getRect(find.byType(Card));
      expect(pill.top, greaterThanOrEqualTo(title.bottom));
      expect(pill.right, card.right - 24);
      // With the width to itself, the title is on one line.
      final text = tester.renderObject<RenderParagraph>(
        find.text('Lock after'),
      );
      final lines = text.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 10),
      );
      expect({for (final box in lines) box.top}, hasLength(1));
    });
  });

  group('a row with a drop-down', () {
    // Rows of each kind the app has: a title alone, with a subtitle, with
    // an icon, and in a sheet with no padding.
    final rows = <String, Widget Function(ChoiceMenu<String> menu)>{
      'plain': (menu) =>
          ChoiceTile(title: const Text('Remind me'), trailing: menu),
      'with a subtitle': (menu) => ChoiceTile(
        title: const Text('Read messages from'),
        subtitle: const Text(
          'For every account you ticked. New messages are always added.',
        ),
        trailing: menu,
      ),
      'with an icon': (menu) => ChoiceTile(
        leading: const RowIcon(Icons.nights_stay_outlined),
        title: const Text('Day ends at'),
        subtitle: const Text('For sales today and Close the day'),
        trailing: menu,
      ),
      'with no padding': (menu) => ChoiceTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Theme'),
        subtitle: const Text('System follows your phone.'),
        trailing: menu,
      ),
    };

    /// The ListTile each row stood for before.
    final before = <String, Widget Function(ChoiceMenu<String> menu)>{
      'plain': (menu) =>
          ListTile(title: const Text('Remind me'), trailing: menu),
      'with a subtitle': (menu) => ListTile(
        title: const Text('Read messages from'),
        subtitle: const Text(
          'For every account you ticked. New messages are always added.',
        ),
        trailing: menu,
      ),
      'with an icon': (menu) => ListTile(
        leading: const RowIcon(Icons.nights_stay_outlined),
        title: const Text('Day ends at'),
        subtitle: const Text('For sales today and Close the day'),
        trailing: menu,
      ),
      'with no padding': (menu) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Theme'),
        subtitle: const Text('System follows your phone.'),
        trailing: menu,
      ),
    };

    for (final kind in rows.keys) {
      testWidgets('$kind is laid out as before at the usual size', (
        tester,
      ) async {
        phone(tester, 1);
        Future<List<Rect>> layout(Widget row) async {
          await tester.pumpWidget(screen([Card(child: row)]));
          return [
            tester.getRect(find.byType(ListTile)),
            for (final text in tester.widgetList<Text>(
              find.descendant(
                of: find.byType(ListTile),
                matching: find.byType(Text),
              ),
            ))
              tester.getRect(find.byWidget(text)),
            tester.getRect(find.byKey(const Key('menu'))),
            if (find.byIcon(Icons.nights_stay_outlined).evaluate().isNotEmpty)
              tester.getRect(find.byIcon(Icons.nights_stay_outlined)),
          ];
        }

        final old = await layout(before[kind]!(menu('Last 12 months')));
        final now = await layout(rows[kind]!(menu('Last 12 months')));
        expect(now, old);
      });

      for (final width in [360.0, 390.0]) {
        testWidgets(
          '$kind keeps its words whole at every text size, $width wide',
          (tester) async {
            for (final scale in accessibilityScales) {
              phone(tester, scale, width: width);
              for (final choice in ['2 am', 'Last 12 months']) {
                await tester.pumpWidget(
                  screen([Card(child: rows[kind]!(menu(choice)))]),
                );
                expect(tester.takeException(), isNull);
                expectWholeWords(
                  tester,
                  find.byType(Card),
                  'with "$choice" at ${scale}x text',
                );
                // Beside its title or under it, the menu ends where the
                // row's padding does.
                final pill = tester.getRect(find.byKey(const Key('menu')));
                final end = kind == 'with no padding' ? 0 : 24;
                expect(
                  pill.right,
                  tester.getRect(find.byType(Card)).right - end,
                );
              }
            }
          },
        );
      }
    }
  });
}
