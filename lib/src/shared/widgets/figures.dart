import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_typography.dart';
import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import 'amounts_hidden.dart';

/// An amount, such as `24,330.50` or `KES 102,865`, laid out as one piece
/// that never breaks: not at its commas or decimal point, and not between
/// its currency code and the number either. When the line before it has
/// no room, the whole amount goes onto a line of its own.
///
/// It is never shrunk or cut to fit. With larger text it grows as Android
/// grows large text (see [figureTextScaler]): small amounts as much as body
/// text, large ones such as a lead card's figure less, but never below
/// their usual size. The layouts around it ([FigureRow], [LabelValueRow]
/// and the lead card) give it a line wide enough. Only where no line on the
/// screen is that wide, as with a seven-figure amount at twice the text
/// size on a narrow phone, does it scroll sideways, still whole, rather
/// than split.
class FigureText extends StatelessWidget {
  const FigureText(this.value, {required this.style, super.key});

  /// Already formatted, and masked while amounts are hidden.
  final String value;
  final TextStyle style;

  /// The width of [value] on one line, currency code and all, at the size
  /// it is drawn: the narrowest line the figure fits on whole.
  static double numberWidth(
    BuildContext context,
    String value,
    TextStyle style,
  ) => _measure(context, value, style, figureTextScaler(context, style)).width;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fits = numberWidth(context, value, style) <= constraints.maxWidth;
      // Never wrapped, so the code and the number stay on one line.
      final text = Text(
        value,
        style: style,
        textScaler: figureTextScaler(context, style),
        softWrap: false,
      );
      return readAsAmount(value, fits ? text : _FadingScroll(child: text));
    },
  );
}

/// How much an amount in [style] grows with the phone's text size. Small
/// amounts grow as body text does; large ones grow less, following the
/// curve Android 14 uses for large text at twice the size (12 to 24, 24 to
/// 36, 40 to about 49), so a lead card's figure stays on one line on a
/// phone. Never smaller than the usual size, and the same as
/// [MediaQuery.textScalerOf] at the usual size.
TextScaler figureTextScaler(BuildContext context, TextStyle style) {
  final base = MediaQuery.textScalerOf(context);
  final size = style.fontSize ?? 14;
  final factor = base.scale(size) / size;
  if (factor <= 1) return base;
  final atDouble = _androidDouble(size);
  final scaled = size + (atDouble - size) * (factor - 1);
  return TextScaler.linear(math.max(1, scaled / size));
}

/// Android 14's size for [size] at twice the text size, between the points
/// it lists; 100 and up do not grow.
double _androidDouble(double size) {
  const points = [
    (8.0, 16.0),
    (10.0, 20.0),
    (12.0, 24.0),
    (14.0, 26.0),
    (18.0, 30.0),
    (20.0, 32.0),
    (24.0, 36.0),
    (30.0, 40.0),
    (100.0, 100.0),
  ];
  if (size <= points.first.$1) return size * 2;
  for (var i = 1; i < points.length; i++) {
    final (x1, y1) = points[i];
    if (size <= x1) {
      final (x0, y0) = points[i - 1];
      return y0 + (y1 - y0) * (size - x0) / (x1 - x0);
    }
  }
  return size;
}

/// [text] in [style] laid out on one line at [scaler], for measuring.
({double width, double minIntrinsicWidth}) _measure(
  BuildContext context,
  String text,
  TextStyle style,
  TextScaler scaler,
) {
  final painter = TextPainter(
    // As the Text draws it: over the text style around it.
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: scaler,
  )..layout();
  final result = (
    width: painter.width,
    minIntrinsicWidth: painter.minIntrinsicWidth,
  );
  painter.dispose();
  return result;
}

/// [child] scrolling sideways, its edges fading out on the side where more
/// of it is hidden, so it reads as cut short on purpose, not as a wrong
/// number. At each end the fade on that side goes.
class _FadingScroll extends StatefulWidget {
  const _FadingScroll({required this.child});

  final Widget child;

  @override
  State<_FadingScroll> createState() => _FadingScrollState();
}

class _FadingScrollState extends State<_FadingScroll> {
  /// How far in from an edge the fade runs.
  static const _fade = 28.0;

  var _atStart = true;
  var _atEnd = false;

  bool _onMetrics(ScrollMetrics m) {
    final atStart = m.pixels <= m.minScrollExtent;
    final atEnd = m.pixels >= m.maxScrollExtent;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Faded where more is hidden: the left edge in left-to-right text is
    // the start.
    final fadeLeft = rtl ? !_atEnd : !_atStart;
    final fadeRight = rtl ? !_atStart : !_atEnd;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final edge = rect.width <= 0
                ? 0.0
                : (_fade / rect.width).clamp(0.0, 0.5);
            return LinearGradient(
              colors: [
                fadeLeft ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                fadeRight ? Colors.transparent : Colors.black,
              ],
              stops: [0, edge, 1 - edge, 1],
            ).createShader(rect);
          },
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The width of [text] on one line in [style], at the phone's text size:
/// for deciding whether things fit side by side.
double textLineWidth(BuildContext context, String text, TextStyle style) =>
    _width(context, text, style);

/// The width of [text] on one line in [style], at the phone's text size.
double _width(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// The widest unbreakable part of [text] in [style], at the phone's text
/// size: the narrowest it can wrap to.
double _minWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.minIntrinsicWidth;
  painter.dispose();
  return width;
}

/// A small card with one figure under its label, such as "Stock value" or
/// "Running low": the label at the top, the figure at the bottom. It starts
/// at [Layout.tileMinHeight] and grows with its text. Put two or three side
/// by side with [FigureRow].
class FigureTile extends StatelessWidget {
  const FigureTile({
    required this.label,
    required this.value,
    this.note,
    this.onTap,
    this.belowZero = false,
    super.key,
  });

  final String label;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  /// Whether [value] is below zero: it then takes the danger colour, as a
  /// lead card's figure does.
  final bool belowZero;

  /// A short line under the figure.
  final String? note;
  final VoidCallback? onTap;

  /// The narrowest this tile can be with its figure whole on one line and
  /// no word of its label or note broken.
  double minWidth(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall!;
    final content = [
      FigureText.numberWidth(
        context,
        value,
        AppTypography.tileFigure(small.color!),
      ),
      _minWidth(context, label, small),
      if (note != null) _minWidth(context, note!, small),
    ].reduce(math.max);
    return content + 2 * Layout.cardPadding;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Layout.tileMinHeight),
          child: Padding(
            padding: const EdgeInsets.all(Layout.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                // Money is never shrunk, cut or split to fit: the figure
                // stays whole and the tile grows.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FigureText(
                      value,
                      style: AppTypography.tileFigure(
                        belowZero
                            // Brand red in light, brightened in dark to
                            // read on a card.
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(height: 4),
                      Text(note!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiles side by side, the same height, [Layout.cardGap] apart. When a
/// tile's figure would not fit whole at that width, as with a long balance
/// or large text, three or more tiles go two to a row, an odd last one at
/// full width; only when two to a row does not fit either do they go one
/// to a row at full width.
class FigureRow extends StatelessWidget {
  const FigureRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final needs = [
      for (final child in children)
        child is FigureTile ? child.minWidth(context) : 0.0,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = children.length;
        final each =
            (constraints.maxWidth - Layout.cardGap * (count - 1)) / count;
        if (needs.every((need) => need <= each)) {
          return _SameHeightRow(
            gap: Layout.cardGap,
            textDirection: Directionality.of(context),
            children: children,
          );
        }
        final half = (constraints.maxWidth - Layout.cardGap) / 2;
        if (count > 2) {
          // Two to a row; an odd last tile has the whole width to itself.
          final paired = count - count % 2;
          final fits = [
            for (var i = 0; i < count; i++)
              needs[i] <= (i < paired ? half : constraints.maxWidth),
          ].every((fit) => fit);
          if (fits) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < count; i += 2) ...[
                  if (i > 0) const SizedBox(height: Layout.cardGap),
                  if (i + 1 < count)
                    _SameHeightRow(
                      gap: Layout.cardGap,
                      textDirection: Directionality.of(context),
                      children: [children[i], children[i + 1]],
                    )
                  else
                    children[i],
                ],
              ],
            );
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: Layout.cardGap),
              child,
            ],
          ],
        );
      },
    );
  }
}

/// Children side by side at equal widths, [gap] apart, all as tall as the
/// tallest. Unlike a [Row] in an [IntrinsicHeight], it lays each child out
/// at its width to find the height, so children may use a [LayoutBuilder].
class _SameHeightRow extends MultiChildRenderObjectWidget {
  const _SameHeightRow({
    required this.gap,
    required this.textDirection,
    required super.children,
  });

  final double gap;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSameHeightRow(gap: gap, textDirection: textDirection);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSameHeightRow renderObject,
  ) => renderObject
    ..gap = gap
    ..textDirection = textDirection;
}

class _SameHeightRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSameHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SameHeightRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SameHeightRowParentData> {
  _RenderSameHeightRow({required this._gap, required this._textDirection});

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SameHeightRowParentData) {
      child.parentData = _SameHeightRowParentData();
    }
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    if (childCount == 0) {
      size = constraints.smallest;
      return;
    }
    final each = (width - _gap * (childCount - 1)) / childCount;
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints.tightFor(width: each), parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    height = constraints.constrainHeight(height);
    var x = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      // At least the row's height, rather than exactly it: a child with
      // tight constraints would lay itself out again on its own when its
      // text changes, and the row would not grow with it.
      child.layout(
        BoxConstraints(minWidth: each, maxWidth: each, minHeight: height),
        parentUsesSize: true,
      );
      final data = child.parentData! as _SameHeightRowParentData;
      data.offset = Offset(
        _textDirection == TextDirection.ltr ? x : width - x - each,
        0,
      );
      x += each + _gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A row with a name, an optional [detail] under it, and a [value] at the
/// end, such as a line on an invoice or in the tax estimate.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({
    required this.label,
    required this.value,
    this.detail,
    this.strong = false,
    this.valueColor,
    this.onTap,
    super.key,
  });

  final String label;
  final String? detail;

  /// The value's colour when it means something, such as
  /// `colors.successText` for money owed to you; the text colour otherwise.
  final Color? valueColor;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  /// A total: the label in bold.
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = strong
        ? theme.textTheme.titleMedium!
        : theme.textTheme.bodyLarge!;
    final detailStyle = theme.textTheme.bodySmall!;
    final valueStyle = AppTypography.rowAmount(
      valueColor ?? theme.colorScheme.onSurface,
    );
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(detail!, style: detailStyle),
        ],
      ],
    );
    final amount = FigureText(value, style: valueStyle);
    // The value sits at the end while the label still fits beside it with
    // no word broken; otherwise it takes its own line under the label, so
    // the amount is never split or squeezed.
    final needs =
        [
          _minWidth(context, label, labelStyle),
          if (detail != null) _minWidth(context, detail!, detailStyle),
        ].reduce(math.max) +
        Layout.cardGap +
        FigureText.numberWidth(context, value, valueStyle);
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardPadding,
        vertical: 12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => needs <= constraints.maxWidth
            ? Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: Layout.cardGap),
                  amount,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  name,
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: amount,
                  ),
                ],
              ),
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
