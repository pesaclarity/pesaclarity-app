import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// The space around every section header: [Layout.sectionTop] above and
/// [Layout.sectionBottom] below. Pass another padding only for a title
/// inside a card or sheet, where the card's own padding sets the space.
const sectionPadding = EdgeInsets.only(
  top: Layout.sectionTop,
  bottom: Layout.sectionBottom,
);

/// A small capitals label over a group of rows, such as `TODAY` over the
/// day's entries or `HISTORY` over an item's moves.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    this.trailing,
    this.padding = sectionPadding,
    super.key,
  });

  /// Written as people say it; it shows in capitals.
  final String text;

  /// A small action or total at the right, such as `In 1,500 · Out 0`.
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!
        .copyWith(color: PesaColors.of(context).textMuted, letterSpacing: 1);
    final label = Semantics(
      header: true,
      child: Text(text.toUpperCase(), semanticsLabel: text, style: style),
    );
    return Padding(
      padding: padding,
      child: trailing == null
          ? label
          // Side by side when both fit; with large text the trailing part
          // drops under the label rather than breaking the label's word.
          : LayoutBuilder(
              builder: (context, constraints) => Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: label,
                  ),
                  trailing!,
                ],
              ),
            ),
    );
  }
}

/// A section's title in sentence case, with an optional [action] at the
/// right, such as "Add a goal".
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    this.action,
    this.padding = sectionPadding,
    super.key,
  });

  final String text;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    return Padding(
      padding: padding,
      child: action == null
          ? title
          : Row(
              children: [
                Expanded(child: title),
                action!,
              ],
            ),
    );
  }
}

/// A tab's title row: the title at the left, then the tab's [actions], with
/// the eye last. Every tab but Home starts with it.
///
/// The title is never shrunk or cut. When it and the actions do not fit on
/// one line, as on a narrow phone with large text, the actions wrap onto
/// the lines under the title, at the right.
///
/// On iPhone the actions sit in a row of their own above the title, at the
/// right, as iOS lays out a large title under its bar's buttons (and as
/// Home does), so the 34 point title never pushes them onto a second line.
class TabHeader extends StatelessWidget {
  const TabHeader(
    this.title, {
    this.semanticsId,
    this.actions = const [],
    super.key,
  });

  final String title;

  /// For UI flows, from `SemanticIds`.
  final String? semanticsId;

  /// Links to the tab's other screens as text buttons, then the eye.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      identifier: semanticsId,
      header: true,
      child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
    );
    final buttons = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    if (actions.isNotEmpty && defaultTargetPlatform == TargetPlatform.iOS) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Layout.titleGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: AlignmentDirectional.centerEnd, child: buttons),
            Align(alignment: AlignmentDirectional.centerStart, child: heading),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.titleGap),
      child: actions.isEmpty
          ? Align(alignment: AlignmentDirectional.centerStart, child: heading)
          : _TitleAndActions(children: [heading, buttons]),
    );
  }
}

/// Lays out a title and its actions: on one line when both fit at their
/// natural widths, otherwise the title on its own line and the actions
/// under it, at the end.
class _TitleAndActions extends MultiChildRenderObjectWidget {
  const _TitleAndActions({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTitleAndActions(Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderTitleAndActions renderObject,
  ) => renderObject.textDirection = Directionality.of(context);
}

class _TitleAndActionsData extends ContainerBoxParentData<RenderBox> {}

class _RenderTitleAndActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TitleAndActionsData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TitleAndActionsData> {
  _RenderTitleAndActions(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TitleAndActionsData) {
      child.parentData = _TitleAndActionsData();
    }
  }

  RenderBox get _title => firstChild!;
  RenderBox get _actions => lastChild!;

  /// Whether the title and the actions fit side by side in [width].
  bool _oneLine(double width) =>
      _title.getMaxIntrinsicWidth(double.infinity) +
          _actions.getMaxIntrinsicWidth(double.infinity) <=
      width;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _title.getMinIntrinsicWidth(height),
    _actions.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _title.getMaxIntrinsicWidth(height) +
      _actions.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(width, (child, w) => child.getMaxIntrinsicHeight(w));

  double _height(double width, double Function(RenderBox, double) height) {
    if (_oneLine(width)) {
      final actions = _actions.getMaxIntrinsicWidth(double.infinity);
      return math.max(
        height(_title, width - actions),
        height(_actions, actions),
      );
    }
    return height(_title, width) + height(_actions, width);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild);
  }

  Size _layout(BoxConstraints constraints, ChildLayouter layoutChild) {
    final width = constraints.maxWidth;
    final dry = layoutChild == ChildLayoutHelper.dryLayoutChild;
    final Size title;
    final Size actions;
    final Offset titleAt;
    final Offset actionsAt;
    if (_oneLine(width)) {
      actions = layoutChild(_actions, const BoxConstraints());
      title = layoutChild(
        _title,
        BoxConstraints(maxWidth: math.max(0, width - actions.width)),
      );
      final height = math.max(title.height, actions.height);
      titleAt = Offset(0, (height - title.height) / 2);
      actionsAt = Offset(width - actions.width, (height - actions.height) / 2);
    } else {
      title = layoutChild(_title, BoxConstraints(maxWidth: width));
      actions = layoutChild(_actions, BoxConstraints(maxWidth: width));
      titleAt = Offset.zero;
      actionsAt = Offset(width - actions.width, title.height);
    }
    final size = constraints.constrain(
      Size(
        width,
        math.max(titleAt.dy + title.height, actionsAt.dy + actions.height),
      ),
    );
    if (!dry) {
      final ltr = _textDirection == TextDirection.ltr;
      Offset place(Offset at, Size child) =>
          ltr ? at : Offset(size.width - at.dx - child.width, at.dy);
      (_title.parentData! as _TitleAndActionsData).offset = place(
        titleAt,
        title,
      );
      (_actions.parentData! as _TitleAndActionsData).offset = place(
        actionsAt,
        actions,
      );
    }
    return size;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
