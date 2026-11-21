import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// [lead], such as a name, with [end], such as an amount or buttons,
/// beside it at the end, as a [Row] with [lead] in an [Expanded] lays them
/// out, while [lead] keeps its widest word's width; otherwise, at larger
/// text, [end] goes under [lead], at the end, so no word in [lead] is drawn
/// across two lines.
class BesideOrUnder
    extends SlottedMultiChildRenderObjectWidget<BesideOrUnderSlot, RenderBox> {
  const BesideOrUnder({
    required this.lead,
    required this.end,
    this.gap = 0,
    this.underGap = 4,
    this.leadMinWidth,
    super.key,
  });

  final Widget lead;
  final Widget end;

  /// The space between [lead] and [end] beside it.
  final double gap;

  /// The space between [lead] and [end] under it.
  final double underGap;

  /// How narrow [lead] can be with no word broken, for a [lead] that
  /// cannot measure itself, such as one holding a [LayoutBuilder]; by
  /// default [lead]'s own narrowest width.
  final double? leadMinWidth;

  @override
  Iterable<BesideOrUnderSlot> get slots => BesideOrUnderSlot.values;

  @override
  Widget childForSlot(BesideOrUnderSlot slot) => switch (slot) {
    BesideOrUnderSlot.lead => lead,
    BesideOrUnderSlot.end => end,
  };

  @override
  RenderBesideOrUnder createRenderObject(BuildContext context) =>
      RenderBesideOrUnder()
        ..gap = gap
        ..underGap = underGap
        ..leadMinWidth = leadMinWidth
        ..textDirection = Directionality.of(context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBesideOrUnder renderObject,
  ) {
    renderObject
      ..gap = gap
      ..underGap = underGap
      ..leadMinWidth = leadMinWidth
      ..textDirection = Directionality.of(context);
  }
}

/// Where each child of [BesideOrUnder] goes.
enum BesideOrUnderSlot { lead, end }

/// The render object of [BesideOrUnder].
class RenderBesideOrUnder extends RenderBox
    with SlottedContainerRenderObjectMixin<BesideOrUnderSlot, RenderBox> {
  double get gap => _gap;
  double _gap = 0;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  double get underGap => _underGap;
  double _underGap = 4;
  set underGap(double value) {
    if (value == _underGap) return;
    _underGap = value;
    markNeedsLayout();
  }

  double? get leadMinWidth => _leadMinWidth;
  double? _leadMinWidth;
  set leadMinWidth(double? value) {
    if (value == _leadMinWidth) return;
    _leadMinWidth = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection = TextDirection.ltr;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _lead => childForSlot(BesideOrUnderSlot.lead)!;
  RenderBox get _end => childForSlot(BesideOrUnderSlot.end)!;

  @override
  Iterable<RenderBox> get children => [
    for (final slot in BesideOrUnderSlot.values) ?childForSlot(slot),
  ];

  BoxParentData _at(RenderBox child) => child.parentData! as BoxParentData;

  ({Size size, Offset lead, Offset end}) _place(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final width = constraints.maxWidth;
    final ltr = textDirection == TextDirection.ltr;
    final beside =
        (leadMinWidth ?? _lead.getMinIntrinsicWidth(double.infinity)) +
            gap +
            _end.getMaxIntrinsicWidth(double.infinity) <=
        width + 0.5;
    final loose = BoxConstraints(maxWidth: width);
    if (beside) {
      final endSize = layoutChild(_end, loose);
      final leadWidth = math.max(0.0, width - endSize.width - gap);
      final leadSize = layoutChild(
        _lead,
        BoxConstraints.tightFor(width: leadWidth),
      );
      final height = math.max(leadSize.height, endSize.height);
      return (
        size: constraints.constrain(Size(width, height)),
        lead: Offset(
          ltr ? 0 : width - leadWidth,
          (height - leadSize.height) / 2,
        ),
        end: Offset(
          ltr ? width - endSize.width : 0,
          (height - endSize.height) / 2,
        ),
      );
    }
    final leadSize = layoutChild(_lead, BoxConstraints.tightFor(width: width));
    final endSize = layoutChild(_end, loose);
    final endY = leadSize.height + underGap;
    return (
      size: constraints.constrain(Size(width, endY + endSize.height)),
      lead: Offset.zero,
      end: Offset(ltr ? width - endSize.width : 0, endY),
    );
  }

  @override
  void performLayout() {
    final placed = _place(constraints, ChildLayoutHelper.layoutChild);
    size = placed.size;
    _at(_lead).offset = placed.lead;
    _at(_end).offset = placed.end;
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _place(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final distance = _lead.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + _at(_lead).offset.dy;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    leadMinWidth ?? _lead.getMinIntrinsicWidth(height),
    _end.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _lead.getMaxIntrinsicWidth(height) +
      gap +
      _end.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(child, offset + _at(child).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final hit = result.addWithPaintOffset(
        offset: _at(child).offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }
}
