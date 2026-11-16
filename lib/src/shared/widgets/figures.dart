import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_typography.dart';
import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// An amount, such as `24,330.50` or `KES 102,865`, laid out as one piece
/// that never breaks inside the number.
///
/// The only place the line may break is the space between a currency code
/// and the number: when both do not fit, the code goes on the line above.
/// The number itself is kept whole: no break at its commas or decimal
/// point, and it is never shrunk or cut to fit. The layouts around it
/// ([FigureRow], [LabelValueRow] and the lead card) give it a line wide
/// enough. Only where no line on the screen is that wide, as with a
/// seven-figure amount at twice the text size on a narrow phone, does the
/// number scroll sideways, still whole, rather than split.
class FigureText extends StatelessWidget {
  const FigureText(this.value, {required this.style, super.key});

  /// Already formatted, and masked while amounts are hidden.
  final String value;
  final TextStyle style;

  /// The width of [value]'s number on one line, without its currency code:
  /// the narrowest line the figure fits on whole. Line breaking never
  /// breaks between digits, or at the commas and decimal point between
  /// them, so this is the widest unbreakable part of [value].
  static double numberWidth(
    BuildContext context,
    String value,
    TextStyle style,
  ) => _minWidth(context, value, style);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final number = numberWidth(context, value, style);
      if (number <= constraints.maxWidth) {
        // The number has no break in it, so a line can only end at the
        // space before it.
        return Text(value, style: style);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(value, style: style, softWrap: false),
      );
    },
  );
}

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
                        belowZero ? colors.danger : theme.colorScheme.onSurface,
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
/// or large text, the tiles go one to a row at full width instead.
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
        _width(context, value, valueStyle);
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
