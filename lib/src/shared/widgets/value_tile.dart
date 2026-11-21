import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A [ListTile] with a value or control at its end, such as an amount, a
/// button or a drop-down. It looks as a [ListTile] does while the title
/// still has its widest word's width beside [trailing]; at larger text,
/// where it would not, [trailing] moves under the title and subtitle, at
/// the end, so no word is broken across two lines. With no [trailing] it
/// is a plain [ListTile].
class ValueTile extends StatelessWidget {
  const ValueTile({
    required this.title,
    this.trailing,
    this.subtitle,
    this.leading,
    this.onTap,
    this.enabled = true,
    this.contentPadding,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;

  /// The space between the title and [trailing] under it.
  static const underGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    if (trailing == null) {
      return ListTile(
        onTap: onTap,
        enabled: enabled,
        leading: leading,
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
      );
    }
    final theme = Theme.of(context);
    final tileTheme = ListTileTheme.of(context);
    final colors = theme.colorScheme;
    final text = theme.textTheme;
    // The styles and spacing ListTile gives its subtitle and trailing.
    final disabled = enabled ? null : theme.disabledColor;
    final subtitleStyle =
        (tileTheme.subtitleTextStyle ??
                text.bodyMedium!.copyWith(color: colors.onSurfaceVariant))
            .copyWith(color: disabled);
    final trailingStyle =
        (tileTheme.leadingAndTrailingTextStyle ??
                text.labelSmall!.copyWith(color: colors.onSurfaceVariant))
            .copyWith(color: disabled);
    final titleStyle =
        tileTheme.titleTextStyle ??
        text.bodyLarge!.copyWith(color: colors.onSurface);
    final density = tileTheme.visualDensity ?? theme.visualDensity;
    return ListTile(
      onTap: onTap,
      enabled: enabled,
      leading: leading,
      contentPadding: contentPadding,
      // The body below lays out the whole tile's height itself.
      minVerticalPadding: 0,
      minTileHeight: 0,
      title: _TileBody(
        title: title,
        subtitle: subtitle == null
            ? null
            : DefaultTextStyle(style: subtitleStyle, child: subtitle!),
        trailing: DefaultTextStyle(style: trailingStyle, child: trailing),
        minVerticalPadding: tileTheme.minVerticalPadding ?? 8,
        gap: (tileTheme.horizontalTitleGap ?? 16) + density.horizontal * 2,
        visualDensity: density,
        titleBaseline: titleStyle.textBaseline ?? TextBaseline.alphabetic,
        subtitleBaseline: subtitleStyle.textBaseline ?? TextBaseline.alphabetic,
        textDirection: Directionality.of(context),
      ),
    );
  }
}

enum _Slot { title, subtitle, trailing }

class _TileBody extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const _TileBody({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.minVerticalPadding,
    required this.gap,
    required this.visualDensity,
    required this.titleBaseline,
    required this.subtitleBaseline,
    required this.textDirection,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget trailing;
  final double minVerticalPadding;
  final double gap;
  final VisualDensity visualDensity;
  final TextBaseline titleBaseline;
  final TextBaseline subtitleBaseline;
  final TextDirection textDirection;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.title => title,
    _Slot.subtitle => subtitle,
    _Slot.trailing => trailing,
  };

  @override
  _RenderTileBody createRenderObject(BuildContext context) =>
      _RenderTileBody()..config = _config;

  @override
  void updateRenderObject(BuildContext context, _RenderTileBody renderObject) {
    renderObject.config = _config;
  }

  _BodyConfig get _config => (
    minVerticalPadding: minVerticalPadding,
    gap: gap,
    visualDensity: visualDensity,
    titleBaseline: titleBaseline,
    subtitleBaseline: subtitleBaseline,
    textDirection: textDirection,
  );
}

typedef _BodyConfig = ({
  double minVerticalPadding,
  double gap,
  VisualDensity visualDensity,
  TextBaseline titleBaseline,
  TextBaseline subtitleBaseline,
  TextDirection textDirection,
});

typedef _Placed = ({Size size, Offset? title, Offset? subtitle, Offset? end});

class _RenderTileBody extends RenderBox
    with SlottedContainerRenderObjectMixin<_Slot, RenderBox> {
  late _BodyConfig _config;
  set config(_BodyConfig value) {
    if (_hasConfig && value == _config) return;
    _config = value;
    _hasConfig = true;
    markNeedsLayout();
  }

  var _hasConfig = false;

  RenderBox get _title => childForSlot(_Slot.title)!;
  RenderBox? get _subtitle => childForSlot(_Slot.subtitle);
  RenderBox get _trailing => childForSlot(_Slot.trailing)!;

  @override
  Iterable<RenderBox> get children => [
    for (final slot in _Slot.values) ?childForSlot(slot),
  ];

  /// Whether the title and subtitle keep their widest word beside the
  /// trailing part at [width].
  bool _beside(double width) {
    final words = math.max(
      _title.getMinIntrinsicWidth(double.infinity),
      _subtitle?.getMinIntrinsicWidth(double.infinity) ?? 0,
    );
    final end = _trailing.getMaxIntrinsicWidth(double.infinity);
    return words + math.max(end + _config.gap, 32) <= width + 0.5;
  }

  /// ListTile's layout when [beside], else the trailing part under the
  /// text, at the end.
  _Placed _place(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
    double? Function(RenderBox, BoxConstraints, TextBaseline) baseline,
  ) {
    final c = _config;
    final width = constraints.maxWidth;
    final ltr = c.textDirection == TextDirection.ltr;
    final pad = c.minVerticalPadding;
    final subtitle = _subtitle;
    if (_beside(width)) {
      final loose = BoxConstraints(maxWidth: width);
      final trailingSize = layoutChild(
        _trailing,
        loose.enforce(
          BoxConstraints(maxHeight: 56 + c.visualDensity.baseSizeAdjustment.dy),
        ),
      );
      final reserved = math.max(trailingSize.width + c.gap, 32.0);
      final text = BoxConstraints.tightFor(width: width - reserved);
      final titleHeight = layoutChild(_title, text).height;
      final double titleY;
      final double height;
      Offset? subtitleAt;
      final target =
          (subtitle == null ? 56.0 : 72.0) +
          c.visualDensity.baseSizeAdjustment.dy;
      if (subtitle == null) {
        height = math.max(target, titleHeight + 2 * pad);
        titleY = (height - titleHeight) / 2;
      } else {
        final subtitleHeight = layoutChild(subtitle, text).height;
        final titleBase =
            baseline(_title, text, c.titleBaseline) ?? titleHeight;
        final subtitleBase =
            baseline(subtitle, text, c.subtitleBaseline) ?? subtitleHeight;
        final targetTitleY = 32.0 - titleBase;
        final targetSubtitleY =
            52.0 + c.visualDensity.vertical * 2 - subtitleBase;
        final halfOverlap =
            math.max(targetTitleY + titleHeight - targetSubtitleY, 0) / 2;
        final idealTitleY = targetTitleY - halfOverlap;
        final idealSubtitleY = targetSubtitleY + halfOverlap;
        final compact =
            idealTitleY < pad || idealSubtitleY + subtitleHeight + pad > target;
        height = compact ? 2 * pad + titleHeight + subtitleHeight : target;
        titleY = compact ? pad : idealTitleY;
        subtitleAt = Offset(
          ltr ? 0 : reserved,
          compact ? pad + titleHeight : idealSubtitleY,
        );
      }
      return (
        size: constraints.constrain(Size(width, height)),
        title: Offset(ltr ? 0 : reserved, titleY),
        subtitle: subtitleAt,
        end: Offset(
          ltr ? width - trailingSize.width : 0,
          (height - trailingSize.height) / 2,
        ),
      );
    }
    final text = BoxConstraints.tightFor(width: width);
    var y = pad;
    final titleAt = Offset(0, y);
    y += layoutChild(_title, text).height;
    Offset? subtitleAt;
    if (subtitle != null) {
      subtitleAt = Offset(0, y);
      y += layoutChild(subtitle, text).height;
    }
    final endSize = layoutChild(_trailing, BoxConstraints(maxWidth: width));
    y += ValueTile.underGap;
    final endAt = Offset(ltr ? width - endSize.width : 0, y);
    y += endSize.height + pad;
    return (
      size: constraints.constrain(Size(width, y)),
      title: titleAt,
      subtitle: subtitleAt,
      end: endAt,
    );
  }

  @override
  void performLayout() {
    final placed = _place(
      constraints,
      ChildLayoutHelper.layoutChild,
      (child, _, type) => child.getDistanceToBaseline(type),
    );
    size = placed.size;
    _at(_title).offset = placed.title!;
    if (_subtitle case final subtitle?) _at(subtitle).offset = placed.subtitle!;
    _at(_trailing).offset = placed.end!;
  }

  BoxParentData _at(RenderBox child) => child.parentData! as BoxParentData;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) => _place(
    constraints,
    ChildLayoutHelper.dryLayoutChild,
    (child, c, type) => child.getDryBaseline(c, type),
  ).size;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final title = _title;
    final distance = title.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance + _at(title).offset.dy;
  }

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    math.max(
      _title.getMinIntrinsicWidth(height),
      _subtitle?.getMinIntrinsicWidth(height) ?? 0,
    ),
    _trailing.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(
        _title.getMaxIntrinsicWidth(height),
        _subtitle?.getMaxIntrinsicWidth(height) ?? 0,
      ) +
      math.max(_trailing.getMaxIntrinsicWidth(height) + _config.gap, 32);

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
  bool hitTestSelf(Offset position) => false;

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
