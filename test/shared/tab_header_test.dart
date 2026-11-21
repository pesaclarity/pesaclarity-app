import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/categoriser/rule_categoriser.dart';
import 'package:pesaclarity/src/domain/spaces/business_setup.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/books/presentation/money_screen.dart';
import 'package:pesaclarity/src/features/business_insights/presentation/business_insights_screen.dart';
import 'package:pesaclarity/src/features/categoriser/application/categoriser_providers.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/insights/presentation/insights_screen.dart';
import 'package:pesaclarity/src/features/people/presentation/people_screen.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/business_setup_providers.dart';
import 'package:pesaclarity/src/features/stock/presentation/stock_screen.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/shared/widgets/marks.dart';
import 'package:pesaclarity/src/shared/widgets/sections.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../domain/fixtures.dart';
import '../helpers/app_fonts.dart';
import '../helpers/test_app.dart';

class _Sells extends BusinessSetupController {
  _Sells(this.sells);

  final BusinessSells sells;

  @override
  Future<BusinessSetup> build() async => BusinessSetup(sells: sells);
}

/// Every tab's title row, on a narrow phone with the largest text and on a
/// common phone with normal text: the title shows whole, never shrunk, and
/// nothing runs past the edge. An overflow reports a Flutter error, which
/// fails the test.
void main() {
  setUpAll(loadAppFonts);

  final screens = <(String, Widget, BusinessSells?)>[
    ('Activity', const ActivityScreen(), null),
    ('Goals', const GoalsScreen(), null),
    ('Plan', const PlanScreen(), null),
    ('Insights', const InsightsScreen(), null),
    ('Money', const MoneyScreen(), BusinessSells.products),
    ('Stock', const StockScreen(), BusinessSells.products),
    ('Services', const StockScreen(), BusinessSells.services),
    ('People', const PeopleScreen(), BusinessSells.products),
    ('Insights', const BusinessInsightsScreen(), BusinessSells.products),
  ];

  for (final (width, scale, iPhone) in [
    (320.0, 2.0, false),
    (390.0, 1.0, false),
    (320.0, 2.0, true),
    (390.0, 1.0, true),
  ]) {
    for (final (title, screen, sells) in screens) {
      final name = sells == null ? title : 'Business $title';
      final platform = iPhone ? ' on iPhone' : '';
      testAppWidgets('$name header fits at ${width.toInt()} dp '
          'and ${scale}x text$platform', (tester) async {
        if (iPhone) debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final db = openTestDatabase();
        final now = eat(2026, 11, 5, 18);
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(() => now),
            // The rules alone: the model's files do not load in a test.
            loadedCategoriserProvider.overrideWithValue(
              const AsyncData(
                LoadedCategoriser(RuleCategoriser(), ModelStatus.notInstalled),
              ),
            ),
            if (sells != null)
              businessSetupProvider.overrideWith(() => _Sells(sells)),
          ],
        );
        addTearDown(container.dispose);
        if (sells == BusinessSells.products) {
          // A product, so Stock shows Count stock as well.
          await tester.runAsync(
            () => container
                .read(stockRepositoryProvider)
                .add(
                  kind: ItemKind.product,
                  name: 'Tomatoes',
                  unit: 'kg',
                  priceMinor: 12000,
                  costMinor: 8000,
                  stockMilli: 6000,
                  at: now,
                ),
          );
        }

        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: AmountsHiddenScope(child: child!),
              ),
              home: screen,
            ),
          ),
        );
        await settleFrames(tester);

        expect(tester.takeException(), isNull);
        final header = find.byType(TabHeader);
        final heading = find.descendant(of: header, matching: find.text(title));
        expect(heading, findsOneWidget);

        // Shown at its full size, on one line, inside the screen.
        final paragraph = tester.renderObject<RenderParagraph>(heading);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: '$title is not cut or wrapped',
        );
        final rect = tester.getRect(heading);
        expect(
          rect.height,
          closeTo(paragraph.size.height, 0.5),
          reason: '$title is not shrunk',
        );
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));

        // Every action stays on the screen.
        for (final button
            in find
                .descendant(of: header, matching: find.byType(Tooltip))
                .evaluate()) {
          final box = button.renderObject! as RenderBox;
          final at = box.localToGlobal(Offset.zero);
          expect(at.dx, greaterThanOrEqualTo(0));
          expect(at.dx + box.size.width, lessThanOrEqualTo(width + 0.5));
          // On iPhone the buttons sit above the title, never beside or
          // under it.
          if (iPhone) {
            expect(at.dy + box.size.height, lessThanOrEqualTo(rect.top + 0.5));
          }
        }
        // The eye is never on a line of its own: beside the title, or
        // beside the other actions.
        final eye = find.descendant(
          of: header,
          matching: find.byType(AmountsEye),
        );
        if (!iPhone && eye.evaluate().isNotEmpty) {
          final at = tester.getRect(eye);
          final others = find
              .descendant(
                of: header,
                matching: find.byWidgetPredicate(
                  (w) => w is PillButton || w is IconButton,
                ),
              )
              .evaluate()
              .map((e) => e.renderObject! as RenderBox)
              .map((b) => b.localToGlobal(Offset.zero) & b.size)
              .where((r) => !at.contains(r.center));
          final besideTitle = at.top < rect.bottom && at.bottom > rect.top;
          final besideAction = others.any(
            (r) => r.top < at.bottom && r.bottom > at.top,
          );
          expect(besideTitle || besideAction || others.isEmpty, isTrue);
        }
        // Before the test ends, so Flutter's debug check passes.
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
