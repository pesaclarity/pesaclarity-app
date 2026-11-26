// Every screen the router can open, on the smallest iPhone the app supports
// (an SE, 375 × 667) with the phone's text at twice the usual size: nothing
// may overflow, and nothing may be drawn past the foot of the screen where
// it cannot be scrolled into view. On iPhone each pushed screen must also
// close with the swipe in from the left edge.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/routing/app_router.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../helpers/app_fonts.dart';
import '../helpers/test_app.dart';

const _size = Size(375, 667);
const _ratio = 3.0;
const _statusBar = 20.0;

/// Every path in [routes] under [parent], with each `:param` filled in.
List<String> _paths(List<RouteBase> routes, [String parent = '']) => [
  for (final route in routes)
    if (route is GoRoute) ...[
      _join(parent, route.path),
      ..._paths(route.routes, _join(parent, route.path)),
    ] else
      ..._paths(route.routes, parent),
];

String _join(String parent, String path) {
  final full = path.startsWith('/')
      ? path
      : '${parent == '/' ? '' : parent}/$path';
  return full.replaceAll(RegExp(r':\w+'), '1');
}

/// What a route needs passed to it to open.
const _extras = <String, Object>{'/home/profile/spaces/join': 'PC-INVITE-1'};

/// Routes that move straight on when there is nothing to show, so there is
/// no screen of their own to check here.
const _passThrough = {
  // Goes on to Home unless there are spaces to choose from.
  '/choose-space',
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Text on screen now that is drawn past the foot of the screen with no
/// list above it that could scroll it into view.
List<String> _cutOff(WidgetTester tester) {
  final cut = <String>[];
  for (final element in find.byType(RichText).evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize || !box.attached) continue;
    if (Scrollable.maybeOf(element) != null) continue;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top + box.size.height > _size.height + 0.5) {
      final text = (element.widget as RichText).text.toPlainText();
      cut.add('"$text" at $top');
    }
  }
  return cut;
}

Future<GoRouter> _openApp(WidgetTester tester, {bool onboarded = true}) async {
  final db = openTestDatabase();
  await pumpApp(
    tester,
    db: db,
    overrides: [launchGateProvider.overrideWithValue(AsyncData(onboarded))],
  );
  await _settle(tester);
  return GoRouter.of(tester.element(find.byType(Navigator).first));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [launchGateProvider.overrideWithValue(const AsyncData(true))],
  );
  final paths = {
    ..._paths(container.read(appRouterProvider).configuration.routes),
  }.where((p) => p != '/' && !_passThrough.contains(p)).toList();
  container.dispose();

  for (final path in paths) {
    testAppWidgets('$path fits an iPhone SE at 2x text', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.runAsync(loadAppFonts);
      tester.view.physicalSize = _size * _ratio;
      tester.view.devicePixelRatio = _ratio;
      const padding = FakeViewPadding(top: _statusBar * _ratio);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // Onboarding's screens only open before it is done.
      final router = await _openApp(
        tester,
        onboarded: !path.startsWith(AppRoutes.onboarding),
      );
      router.go(path, extra: _extras[path]);
      await _settle(tester);
      // Scroll each list to its end and back, so the rows below the fold
      // are laid out too: an overflow among them fails the test.
      for (final list in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      )) {
        final position = list.position;
        if (axisDirectionToAxis(list.axisDirection) != Axis.vertical ||
            !position.hasContentDimensions) {
          continue;
        }
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        position.jumpTo(0);
        await tester.pump();
      }
      final cut = _cutOff(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
      expect(cut, isEmpty, reason: 'text past the foot of $path');
    });
  }

  testAppWidgets('a pushed screen swipes back on iPhone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final db = openTestDatabase();
    await pumpApp(
      tester,
      db: db,
      overrides: [launchGateProvider.overrideWithValue(const AsyncData(true))],
    );
    await _settle(tester);
    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    for (final (from, to) in [
      ('/home/profile/backup', '/home/profile'),
      ('/goals/debts', '/goals'),
      ('/ask/settings', '/ask'),
    ]) {
      router.go(from);
      await _settle(tester);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.dragFrom(const Offset(2, 300), Offset(width * 0.9, 0));
      await _settle(tester);
      expect(
        router.state.matchedLocation,
        to,
        reason: 'swiping back from $from',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
