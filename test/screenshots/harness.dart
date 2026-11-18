// Shared set-up for the marketing screenshots (README, Screenshots).
//
// The screens are the app's own widgets, filled with made-up records and
// drawn with the app's real fonts, at a phone size, in light and dark. They
// only run when asked for, so the normal test run skips them:
//
//   tool/screenshots.sh [out-dir]
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/home/presentation/add_menu.dart';
import 'package:pesaclarity/src/features/look/presentation/field_style_theme.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/app_fonts.dart';
import '../helpers/test_app.dart';

/// Set by tool/screenshots.sh; without it every screenshot test is skipped.
const generateScreenshots = bool.fromEnvironment('SCREENSHOTS');

/// Where the PNGs go.
const screenshotsDir = String.fromEnvironment(
  'SCREENSHOTS_OUT',
  defaultValue: 'build/screenshots',
);

/// A 390 × 844 phone at 3x: 1170 × 2532 pixels.
const phoneSize = Size(1170, 2532);
const phonePixelRatio = 3.0;

/// The status bar's height, in logical pixels.
const statusBarHeight = 47.0;

/// The theme the screen being drawn uses.
ThemeData get shotTheme => _dark ? AppTheme.dark : AppTheme.light;
var _dark = false;

/// A [MaterialApp] as the app builds one, in [shotTheme].
Widget shotApp(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: shotTheme,
      builder: (context, child) =>
          AmountsHiddenScope(child: FieldStyleTheme(child: child!)),
      home: home,
    );

/// [body] in the tab bar with the + beside it, as the app's shell shows
/// it; over [root] when given, so it has a back arrow.
Widget tabShell(
  Widget body, {
  required List<PillDestination> tabs,
  required int index,
  Widget? root,
}) => Scaffold(
  body: root == null
      ? body
      : Navigator(
          onGenerateInitialRoutes: (_, _) => [
            MaterialPageRoute<void>(builder: (_) => root),
            MaterialPageRoute<void>(builder: (_) => body),
          ],
        ),
  bottomNavigationBar: SafeArea(
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
    child: Row(
      children: [
        Expanded(
          child: PillNavigationBar(
            destinations: tabs,
            selectedIndex: index,
            onSelected: (_) {},
          ),
        ),
        const SizedBox(width: 12),
        const MainAddButton(),
      ],
    ),
  ),
);

/// Registers screen [name] twice, light and dark. [body] pumps the screen
/// (using [shotApp] or [shotTheme]) and calls [snap] with the file stem.
///
/// [statusBar] leaves a status bar's worth of space at the top.
void screenshot(
  String name,
  Future<void> Function(WidgetTester tester) body, {
  bool statusBar = true,
}) {
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('$name ($theme)', skip: !generateScreenshots, (tester) async {
      _dark = dark;
      // Tests draw shadows as solid outlines unless told otherwise.
      debugDisableShadows = false;
      try {
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = phoneSize;
        tester.view.devicePixelRatio = phonePixelRatio;
        if (statusBar) {
          const top = FakeViewPadding(top: statusBarHeight * phonePixelRatio);
          tester.view.padding = top;
          tester.view.viewPadding = top;
        }
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _current = '$name-$theme';
        await body(tester);
      } finally {
        debugDisableShadows = true;
        _dark = false;
      }
      // Unmount, so Drift's stream queries close inside the fake clock.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  }
}

String? _current;

/// Writes what is on screen now to `<name>-<theme>.png`, or, with [variant],
/// `<variant>-<theme>.png` for a second screen from the same test.
Future<void> snap(WidgetTester tester, {String? variant}) async {
  await settleFrames(tester);
  final stem = variant == null
      ? _current!
      : '$variant-${_dark ? 'dark' : 'light'}';
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & phoneSize);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(screenshotsDir).createSync(recursive: true);
    File('$screenshotsDir/$stem.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

var _fontsLoaded = false;

/// The app's fonts and the Material icons, in place of the test font whose
/// every glyph is a square.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  await loadAppFonts();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  _fontsLoaded = true;
}
