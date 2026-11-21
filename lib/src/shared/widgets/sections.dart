import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import 'amounts_hidden.dart';
import 'beside_or_under.dart';

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
          // The action moves under the title at larger text, where the
          // title would otherwise break a word.
          : BesideOrUnder(lead: title, end: action!),
    );
  }
}

/// A tab's title row: the title at the left, then the tab's [actions], with
/// the eye last. Every tab but Home starts with it.
///
/// The title is never shrunk or cut. When it and the actions do not fit on
/// one line, as on a narrow phone with large text, the eye stays beside the
/// title, at the right, and the other actions wrap onto the lines under it,
/// at the right, so they never crowd the title or leave the eye on a line
/// of its own.
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
    Widget wrap(List<Widget> children) => Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
    final buttons = wrap(actions);
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
          : actions.length > 1 && actions.last is AmountsEye
          ? _TitleAndActions(
              children: [
                heading,
                wrap(_withoutGap(actions.sublist(0, actions.length - 1))),
                actions.last,
              ],
            )
          : _TitleAndActions(children: [heading, buttons]),
    );
  }
}

/// [actions] without a trailing gap, left where the eye was taken off.
List<Widget> _withoutGap(List<Widget> actions) =>
    actions.isNotEmpty && actions.last is SizedBox
    ? actions.sublist(0, actions.length - 1)
    : actions;

/// Lays out a title and its actions: on one line when both fit at their
/// natural widths, otherwise the title on its own line and the actions
/// under it, at the end. With a third child, the eye, it follows the other
/// actions on one line, and otherwise stays on the title's line at the end
/// while they go under it (unless the title and the eye do not fit side by
/// side either, when it goes under with them).
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
  RenderBox get _actions => childAfter(firstChild!)!;

  /// The eye, when it is kept apart from the other actions.
  RenderBox? get _eye => childAfter(_actions);

  double _eyeWidth() => _eye?.getMaxIntrinsicWidth(double.infinity) ?? 0;

  /// Whether the title and the actions fit side by side in [width].
  bool _oneLine(double width) =>
      _title.getMaxIntrinsicWidth(double.infinity) +
          _actions.getMaxIntrinsicWidth(double.infinity) +
          _eyeWidth() <=
      width;

  /// Whether, when not on one line, the eye stays beside the title.
  bool _eyeWithTitle(double width) =>
      _eye != null &&
      _title.getMaxIntrinsicWidth(double.infinity) + _eyeWidth() <= width;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _title.getMinIntrinsicWidth(height),
    _actions.getMinIntrinsicWidth(height) +
        (_eye?.getMinIntrinsicWidth(height) ?? 0),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _title.getMaxIntrinsicWidth(height) +
      _actions.getMaxIntrinsicWidth(height) +
      (_eye?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _height(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _height(width, (child, w) => child.getMaxIntrinsicHeight(w));

  double _height(double width, double Function(RenderBox, double) height) {
    final eye = _eye;
    final eyeWidth = _eyeWidth();
    if (_oneLine(width)) {
      final actions = _actions.getMaxIntrinsicWidth(double.infinity);
      return [
        height(_title, width - actions - eyeWidth),
        height(_actions, actions),
        if (eye != null) height(eye, eyeWidth),
      ].reduce(math.max);
    }
    if (eye != null && _eyeWithTitle(width)) {
      return math.max(height(_title, width - eyeWidth), height(eye, eyeWidth)) +
          height(_actions, width);
    }
    if (eye != null) {
      return height(_title, width) +
          math.max(height(_actions, width - eyeWidth), height(eye, eyeWidth));
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
    final eye = _eye;
    final Size title;
    final Size actions;
    var eyeSize = Size.zero;
    final Offset titleAt;
    final Offset actionsAt;
    var eyeAt = Offset.zero;
    if (_oneLine(width)) {
      actions = layoutChild(_actions, const BoxConstraints());
      if (eye != null) eyeSize = layoutChild(eye, const BoxConstraints());
      title = layoutChild(
        _title,
        BoxConstraints(
          maxWidth: math.max(0, width - actions.width - eyeSize.width),
        ),
      );
      final height = [
        title.height,
        actions.height,
        eyeSize.height,
      ].reduce(math.max);
      titleAt = Offset(0, (height - title.height) / 2);
      actionsAt = Offset(
        width - actions.width - eyeSize.width,
        (height - actions.height) / 2,
      );
      eyeAt = Offset(width - eyeSize.width, (height - eyeSize.height) / 2);
    } else if (eye != null && _eyeWithTitle(width)) {
      // The eye beside the title; the other actions under them.
      eyeSize = layoutChild(eye, const BoxConstraints());
      title = layoutChild(
        _title,
        BoxConstraints(maxWidth: math.max(0, width - eyeSize.width)),
      );
      final line = math.max(title.height, eyeSize.height);
      titleAt = Offset(0, (line - title.height) / 2);
      eyeAt = Offset(width - eyeSize.width, (line - eyeSize.height) / 2);
      actions = layoutChild(_actions, BoxConstraints(maxWidth: width));
      actionsAt = Offset(width - actions.width, line);
    } else {
      title = layoutChild(_title, BoxConstraints(maxWidth: width));
      titleAt = Offset.zero;
      if (eye != null) eyeSize = layoutChild(eye, const BoxConstraints());
      actions = layoutChild(
        _actions,
        BoxConstraints(maxWidth: math.max(0, width - eyeSize.width)),
      );
      final line = math.max(actions.height, eyeSize.height);
      actionsAt = Offset(
        width - actions.width - eyeSize.width,
        title.height + (line - actions.height) / 2,
      );
      eyeAt = Offset(
        width - eyeSize.width,
        title.height + (line - eyeSize.height) / 2,
      );
    }
    final size = constraints.constrain(
      Size(
        width,
        [
          titleAt.dy + title.height,
          actionsAt.dy + actions.height,
          eyeAt.dy + eyeSize.height,
        ].reduce(math.max),
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
      if (eye != null) {
        (eye.parentData! as _TitleAndActionsData).offset = place(
          eyeAt,
          eyeSize,
        );
      }
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
