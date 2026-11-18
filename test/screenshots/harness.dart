// Shared set-up for the marketing screenshots (README, Screenshots).
//
// The screens are the app's own widgets, filled with made-up records and
// drawn with the app's real fonts, at a phone size, in light and dark. They
// only run when asked for, so the normal test run skips them:
//
//   tool/screenshots.sh [out-dir]
//
// The same screens make the accessibility check (tool/accessibility.sh):
// each at the phone's larger text sizes, in light, dark and high contrast,
// failing on anything that overflows, an amount cut short, a field's label
// cut short, a row name in Activity or Money cut before its second line, a
// tap target that is too small or a button with no label. Text contrast is
// only reported, apart from the screens in tool/accessibility.sh's list.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/home/presentation/add_menu.dart';
import 'package:pesaclarity/src/features/look/presentation/field_style_theme.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/accessibility.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/shared/widgets/marks.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/app_fonts.dart';
import '../helpers/test_app.dart';

/// Set by tool/screenshots.sh; without it every screenshot test is skipped.
const generateScreenshots = bool.fromEnvironment('SCREENSHOTS');

/// Set by `tool/screenshots.sh --iphone`: draw the screens as an iPhone
/// shows them, with the home indicator's space at the foot.
const iPhoneScreenshots = bool.fromEnvironment('SCREENSHOTS_IPHONE');

/// The home indicator's space at the foot of an iPhone, in points.
const homeIndicatorHeight = 34.0;

/// Where the PNGs go.
const screenshotsDir = String.fromEnvironment(
  'SCREENSHOTS_OUT',
  defaultValue: 'build/screenshots',
);

/// Set by tool/accessibility.sh: every screen at [accessibilityScales] in
/// light and dark, and at the usual size in high contrast too.
const checkAccessibility = bool.fromEnvironment('ACCESSIBILITY');

/// Where the accessibility check writes its contrast report and, when
/// [accessibilityShots] is set, a PNG of each screen at each size.
const accessibilityDir = String.fromEnvironment(
  'ACCESSIBILITY_OUT',
  defaultValue: 'build/accessibility',
);

/// Whether the accessibility check saves what each screen looks like.
const accessibilityShots = bool.fromEnvironment('ACCESSIBILITY_SHOTS');

/// The text sizes the phone's settings offer that the screens must fit:
/// the usual, then larger up to twice the size.
const accessibilityScales = [1.0, 1.3, 1.5, 2.0];

/// A 390 × 844 phone at 3x: 1170 × 2532 pixels.
const phoneSize = Size(1170, 2532);
const phonePixelRatio = 3.0;

/// The status bar's height, in logical pixels.
const statusBarHeight = 47.0;

/// The theme the screen being drawn uses.
ThemeData get shotTheme => _contrast
    ? (_dark ? AppTheme.darkHighContrast : AppTheme.lightHighContrast)
    : (_dark ? AppTheme.dark : AppTheme.light);
var _dark = false;

/// A [MaterialApp] as the app builds one, in [shotTheme].
Widget shotApp(Widget home, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: shotTheme,
      builder: (context, child) => Theme(
        data: accessibleTheme(context, Theme.of(context)),
        child: AmountsHiddenScope(child: FieldStyleTheme(child: child!)),
      ),
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
///
/// With [checkAccessibility] it registers the screen once for each text
/// size in [accessibilityScales] and theme instead, and [snap] checks it.
void screenshot(
  String name,
  Future<void> Function(WidgetTester tester) body, {
  bool statusBar = true,
}) {
  if (checkAccessibility) {
    for (final scale in accessibilityScales) {
      for (final (dark, contrast) in [
        (false, false),
        (true, false),
        if (scale == 1.0) ...[(false, true), (true, true)],
      ]) {
        final theme =
            '${contrast ? 'contrast-' : ''}${dark ? 'dark' : 'light'}';
        testWidgets('$name at ${scale}x text ($theme)', (tester) async {
          _scale = scale;
          _contrast = contrast;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          if (contrast) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(highContrast: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
          }
          final handle = tester.ensureSemantics();
          try {
            await _draw(
              tester,
              name,
              dark,
              '$theme-${scale}x',
              statusBar,
              body,
            );
          } finally {
            handle.dispose();
            _scale = 1;
            _contrast = false;
          }
        });
      }
    }
    return;
  }
  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    testWidgets('$name ($theme)', skip: !generateScreenshots, (tester) async {
      await _draw(tester, name, dark, theme, statusBar, body);
    });
  }
}

Future<void> _draw(
  WidgetTester tester,
  String name,
  bool dark,
  String suffix,
  bool statusBar,
  Future<void> Function(WidgetTester tester) body,
) async {
  _dark = dark;
  // Tests draw shadows as solid outlines unless told otherwise.
  debugDisableShadows = false;
  try {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = phoneSize;
    tester.view.devicePixelRatio = phonePixelRatio;
    var top = 0.0;
    var bottom = 0.0;
    if (statusBar) top = statusBarHeight * phonePixelRatio;
    if (iPhoneScreenshots) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      bottom = homeIndicatorHeight * phonePixelRatio;
    }
    if (top > 0 || bottom > 0) {
      final padding = FakeViewPadding(top: top, bottom: bottom);
      tester.view.padding = padding;
      tester.view.viewPadding = padding;
    }
    tester.platformDispatcher.platformBrightnessTestValue = dark
        ? Brightness.dark
        : Brightness.light;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    _name = name;
    _current = '$name-$suffix';
    await body(tester);
  } finally {
    debugDisableShadows = true;
    _dark = false;
  }
  // Unmount, so Drift's stream queries close inside the fake clock.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  debugDefaultTargetPlatformOverride = null;
}

var _scale = 1.0;
var _contrast = false;
String? _name;

String? _current;

/// Writes what is on screen now to `<name>-<theme>.png`, or, with [variant],
/// `<variant>-<theme>.png` for a second screen from the same test.
Future<void> snap(WidgetTester tester, {String? variant}) async {
  await settleFrames(tester);
  if (checkAccessibility) {
    if (accessibilityShots) await _write(tester, variant);
    await _check(tester, variant ?? _name!);
    await _scrollThrough(tester, variant ?? _name!);
    return;
  }
  await _write(tester, variant);
}

Future<void> _write(WidgetTester tester, String? variant) async {
  final stem = checkAccessibility
      ? '${variant ?? _name}-${_current!.substring(_name!.length + 1)}'
      : variant == null
      ? _current!
      : '$variant-${_dark ? 'dark' : 'light'}';
  final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & phoneSize);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    const dir = checkAccessibility ? accessibilityDir : screenshotsDir;
    Directory(dir).createSync(recursive: true);
    File('$dir/$stem.png').writeAsBytesSync(bytes!.buffer.asUint8List());
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

/// The accessibility checks on what is on screen now, as [screen]: nothing
/// overflowing (Flutter reports that as an error, which fails the test), no
/// amount cut short, tap targets big enough on Android and iPhone, and a
/// label on everything that can be tapped. Text contrast is written to the
/// report, not failed on.
Future<void> _check(WidgetTester tester, String screen) async {
  // An overflow needs no check here: Flutter reports it as an error, with
  // the widget that overflowed, and the test fails when it ends.
  _expectNothingCut(tester, screen);
  if (const bool.fromEnvironment('DUMP')) {
    debugDumpSemanticsTree();
  }
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (_scale == 1.0) {
    final contrast = await textContrastGuideline.evaluate(tester);
    _report('contrast', screen, {
      'passed': contrast.passed,
      'reason': contrast.reason,
    });
  }
}

/// An amount such as `1,200`, `24.50`, `KES 950` or `KES •••••`.
final _amount = RegExp(
  r'\d{1,3}(?:,\d{3})+|\d\.\d{2}\b|\b[A-Z]{3} (?:\d|•)|•••',
);

/// Fails when an amount on screen is cut short: ellipsized, clipped or
/// narrower than its number, as amounts are always shown whole. Fails too
/// when a field's label is cut short (labels sit above their field and
/// wrap), or when a row name in Activity or Money ends in "..." before it
/// has used its second line. Other text that runs out of its lines, such as
/// a long name ellipsized after two lines, is written to the report.
void _expectNothingCut(WidgetTester tester, String screen) {
  final cut = <String>[];
  final labels = <String>[];
  final names = <String>[];
  final shortened = <String>[];
  void visit(RenderObject object) {
    if (object is RenderParagraph &&
        object.attached &&
        object.hasSize &&
        !object.debugNeedsLayout) {
      final text = object.text.toPlainText();
      final hasAmount = text.contains(_amount);
      final element = switch (object.debugCreator) {
        final DebugCreator c => c.element,
        _ => null,
      };
      final decorator = element
          ?.findAncestorWidgetOfExactType<InputDecorator>()
          ?.decoration;
      final isLabel = decorator != null && decorator.labelText == text;
      final clipped =
          !object.softWrap &&
          object.size.width + 0.5 <
              object.getMaxIntrinsicWidth(double.infinity);
      if (isLabel && (object.didExceedMaxLines || clipped)) {
        labels.add('"$text" is cut, in ${_creator(object)}');
      }
      if (element?.findAncestorWidgetOfExactType<RowName>() != null &&
          object.didExceedMaxLines &&
          _lineCount(object) < RowName.maxLines) {
        names.add('"$text" is cut on one line, in ${_creator(object)}');
      }
      if (object.didExceedMaxLines) {
        (hasAmount ? cut : shortened).add(
          '"$text" runs out of its lines, in ${_creator(object)}',
        );
      } else if (!hasAmount) {
        // On one line and wider than its box: faded or clipped at the edge.
        if (!object.softWrap &&
            !_inHorizontalScroll(object) &&
            object.size.width + 0.5 <
                object.getMaxIntrinsicWidth(double.infinity)) {
          shortened.add('"$text" is clipped, in ${_creator(object)}');
        }
      } else {
        // Its widest unbreakable part, the number, must fit, and on one
        // line all of it must, unless it scrolls sideways (FigureText's
        // last resort).
        final whole = object.softWrap
            ? object.getMinIntrinsicWidth(double.infinity)
            : object.getMaxIntrinsicWidth(double.infinity);
        final scrolls = _inHorizontalScroll(object);
        if (!scrolls && object.size.width + 0.5 < whole) {
          cut.add(
            '"$text" is cut: ${object.size.width} of $whole wide, in '
            '${_creator(object)}',
          );
        }
      }
    }
    object.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    view.visitChildren(visit);
  }
  if (shortened.isNotEmpty) {
    _report('shortened', screen, {'text': shortened});
  }
  expect(cut, isEmpty, reason: 'An amount is cut short at ${_scale}x text');
  expect(
    labels,
    isEmpty,
    reason: "A field's label is cut short at ${_scale}x text",
  );
  expect(
    names,
    isEmpty,
    reason: 'A row name is cut before its second line at ${_scale}x text',
  );
}

/// How many lines [text] is drawn on.
int _lineCount(RenderParagraph text) => {
  for (final box in text.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.text.toPlainText().length),
  ))
    box.top.round(),
}.length;

/// Adds a line to `<kind>.jsonl` in [accessibilityDir].
void _report(String kind, String screen, Map<String, Object?> fields) {
  final theme = '${_contrast ? 'contrast-' : ''}${_dark ? 'dark' : 'light'}';
  Directory(accessibilityDir).createSync(recursive: true);
  File('$accessibilityDir/$kind.jsonl').writeAsStringSync(
    '${jsonEncode({'screen': screen, 'theme': theme, 'scale': _scale, ...fields})}\n',
    mode: FileMode.append,
  );
}

/// The widget [object] was built by, with where in the app's code.
String _creator(RenderObject object) {
  final creator = object.debugCreator;
  if (creator is! DebugCreator) return '$creator';
  final where = debugTransformDebugCreator([DiagnosticsDebugCreator(creator)])
      .map((n) => n.toStringDeep().replaceAll('\n', ' '))
      .join(' ');
  return '${creator.element.debugGetCreatorChain(4)} $where';
}

/// Scrolls each list on screen to its end and back, a screenful at a
/// time, so the rows below the fold are laid out and checked too: an
/// overflow among them fails the test, as does an amount cut short.
Future<void> _scrollThrough(WidgetTester tester, String screen) async {
  final lists = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where(
        (s) =>
            axisDirectionToAxis(s.axisDirection) == Axis.vertical &&
            s.position.maxScrollExtent > 0,
      )
      .toList();
  for (final list in lists) {
    final position = list.position;
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension * 0.8,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
      _expectNothingCut(tester, screen);
    }
    position.jumpTo(0);
    await tester.pump();
  }
}

bool _inHorizontalScroll(RenderObject object) {
  for (var p = object.parent; p != null; p = p.parent) {
    if (p is RenderViewportBase && p.axis == Axis.horizontal) return true;
  }
  return false;
}
