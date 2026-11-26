import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A [GoRoute] whose screen is shown in a page the app picks itself, rather
/// than one go_router picks from the type of app around it.
///
/// go_router looks for its own `MaterialApp` above the router; when it does
/// not find one it falls back to pages with no transition, and so no swipe
/// back on iPhone. Here iPhone always gets a [MaterialPage], which takes the
/// theme's slide from the right and the edge swipe back with it. Android
/// keeps the screens changing in place, as they always have.
class AppRoute extends GoRoute {
  AppRoute({
    required super.path,
    required GoRouterWidgetBuilder builder,
    super.routes,
  }) : super(
         pageBuilder: (context, state) =>
             appPage(state, builder(context, state)),
       );
}

/// The page [child] is shown in for [state]: see [AppRoute].
Page<void> appPage(GoRouterState state, Widget child) =>
    defaultTargetPlatform == TargetPlatform.iOS
    ? MaterialPage<void>(
        key: state.pageKey,
        name: state.name ?? state.path,
        arguments: <String, String>{
          ...state.pathParameters,
          ...state.uri.queryParameters,
        },
        restorationId: state.pageKey.value,
        child: child,
      )
    : NoTransitionPage<void>(
        key: state.pageKey,
        name: state.name ?? state.path,
        arguments: <String, String>{
          ...state.pathParameters,
          ...state.uri.queryParameters,
        },
        restorationId: state.pageKey.value,
        child: child,
      );
