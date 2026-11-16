import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/books/report_setup.dart' show ReportColour;
import 'brand_tokens.dart';
import 'pesa_colors.dart';

/// The colours every PDF the app makes is drawn in: invoices, receipts,
/// statements, reports, exports and slips.
///
/// Print is always light, so each palette is built from the light theme's
/// tokens. Brand red is kept for the accent: the logo mark, the thin rule
/// (or the full band an owner chooses) at the top. Titles, figures and body
/// text are in the text colour, and table headers and lines are neutral.
/// Lines and fills are a step stronger than on screen, so they survive an
/// A4 laser or a thermal till printer.
@immutable
class PdfPalette {
  const PdfPalette({
    required this.accent,
    required this.onAccent,
    required this.text,
    required this.muted,
    required this.line,
    required this.headerFill,
    required this.panel,
    required this.bar,
    required this.barTrack,
    required this.success,
    required this.successFill,
    required this.warning,
  });

  /// The app's light theme, in colour.
  static final PdfPalette light = PdfPalette(
    accent: _pdf(BrandTokens.brand),
    onAccent: _pdf(BrandTokens.onBrand),
    text: _pdf(BrandTokens.text),
    muted: _pdf(PesaColors.light.textMuted),
    // The screen's border is too faint to print; the high-contrast border
    // is the same neutral, one step darker.
    line: _pdf(PesaColors.lightHighContrast.border),
    headerFill: _pdf(PesaColors.light.selected),
    panel: _pdf(BrandTokens.background),
    bar: _pdf(BrandTokens.text),
    barTrack: _pdf(PesaColors.light.selected),
    success: _pdf(PesaColors.light.successText),
    successFill: _pdf(PesaColors.light.successSoft),
    warning: _pdf(PesaColors.light.warning),
  );

  /// Grey and black: [light] with the accent in the text colour, for a
  /// formal report.
  static final PdfPalette formal = light.copyWith(accent: light.text);

  /// Black and white with no fills, for a thermal till printer.
  static const PdfPalette mono = PdfPalette(
    accent: PdfColors.black,
    onAccent: PdfColors.white,
    text: PdfColors.black,
    muted: PdfColors.black,
    line: PdfColors.black,
    headerFill: null,
    panel: null,
    bar: PdfColors.black,
    barTrack: null,
    success: PdfColors.black,
    successFill: null,
    warning: PdfColors.black,
  );

  /// The palette for a receipt, in colour or black and white.
  static PdfPalette receipt({required bool blackAndWhite}) =>
      blackAndWhite ? mono : light;

  /// The palette for a business report in the colour its style asks for.
  static PdfPalette report(ReportColour colour) => switch (colour) {
    ReportColour.brand => light,
    ReportColour.formal => formal,
  };

  /// The logo mark, the rule along the top and an owner's full band.
  final PdfColor accent;

  /// Text and the initials box on [accent].
  final PdfColor onAccent;

  /// Body text, titles and figures.
  final PdfColor text;

  /// Labels, notes and footers.
  final PdfColor muted;

  /// Table lines, dividers and box edges.
  final PdfColor line;

  /// Behind a table's header row; none in black and white.
  final PdfColor? headerFill;

  /// Behind a note or summary box; none in black and white.
  final PdfColor? panel;

  /// A bar in a chart.
  final PdfColor bar;

  /// Behind a bar, its full length; none in black and white.
  final PdfColor? barTrack;

  /// Good news, such as Paid.
  final PdfColor success;

  /// Behind [success] text; none in black and white, which outlines it.
  final PdfColor? successFill;

  /// Something to check, such as leakage as a share of income.
  final PdfColor warning;

  /// Every colour in this palette.
  List<PdfColor> get all => [
    accent,
    onAccent,
    text,
    muted,
    line,
    ?headerFill,
    ?panel,
    bar,
    ?barTrack,
    success,
    ?successFill,
    warning,
  ];

  /// The PDF's base theme: the built-in fonts, with body text in [text]
  /// at [fontSize].
  pw.ThemeData theme({double fontSize = 10}) {
    final base = pw.ThemeData.base();
    return base.copyWith(
      defaultTextStyle: base.defaultTextStyle.copyWith(
        color: text,
        fontSize: fontSize,
      ),
    );
  }

  PdfPalette copyWith({PdfColor? accent}) => PdfPalette(
    accent: accent ?? this.accent,
    onAccent: onAccent,
    text: text,
    muted: muted,
    line: line,
    headerFill: headerFill,
    panel: panel,
    bar: bar,
    barTrack: barTrack,
    success: success,
    successFill: successFill,
    warning: warning,
  );

  static PdfColor _pdf(Color c) => PdfColor.fromInt(c.toARGB32());
}
