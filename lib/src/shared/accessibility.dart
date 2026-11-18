import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

// Following the phone's accessibility settings.
//
// Less motion: Android's "Remove animations" and iPhone's "Reduce Motion".
// Things then change in place, without sliding, growing or fading.

/// Whether the phone asks for less motion.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [duration], or none when the phone asks for less motion.
Duration motionDuration(BuildContext context, Duration duration) =>
    reduceMotion(context) ? Duration.zero : duration;

/// [theme] with page transitions that respect less motion: a new screen
/// shows at once instead of zooming in. iPhone keeps its slide, which
/// carries the swipe back and which iOS keeps with Reduce Motion too.
ThemeData withReducedMotion(ThemeData theme) => theme.copyWith(
  pageTransitionsTheme: _ReducedMotionTransitions(theme.pageTransitionsTheme),
);

class _ReducedMotionTransitions extends PageTransitionsTheme {
  const _ReducedMotionTransitions(this.usual);

  final PageTransitionsTheme usual;

  @override
  Map<TargetPlatform, PageTransitionsBuilder> get builders => usual.builders;

  @override
  DelegatedTransitionBuilder? delegatedTransition(TargetPlatform platform) =>
      usual.delegatedTransition(platform);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    final builder = usual.builders[platform];
    if (reduceMotion(context) && builder is! CupertinoPageTransitionsBuilder) {
      return child;
    }
    return usual.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
