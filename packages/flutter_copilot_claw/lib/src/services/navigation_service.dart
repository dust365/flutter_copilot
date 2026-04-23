import 'dart:async';

import 'package:flutter/widgets.dart';

/// Service for controlling Flutter app navigation through VM service extensions.
class NavigationService {
  /// Finds the root [NavigatorState] by walking descendants of the root element.
  ///
  /// `WidgetsBinding.instance.rootElement` is an ancestor of `MaterialApp`, so
  /// `Navigator.of(rootElement)` always fails. Instead we locate the first
  /// `NavigatorState` in the element tree (which is the root Navigator created
  /// by `MaterialApp` / `WidgetsApp`).
  NavigatorState? _findRootNavigator() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;

    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  NavigatorState _requireNavigator() {
    final navigator = _findRootNavigator();
    if (navigator == null) {
      throw Exception(
        'No Navigator found in the widget tree. '
        'Ensure the app uses MaterialApp/CupertinoApp/WidgetsApp.',
      );
    }
    return navigator;
  }

  /// Pushes a new route onto the navigator.
  ///
  /// [route] is the named route to push. [arguments] are passed to the route.
  ///
  /// Note: This does NOT await the pushed route's completion — the returned
  /// [Future] from `pushNamed` only completes when the route is popped, so
  /// awaiting it would block the MCP call indefinitely.
  Future<void> push({
    String? route,
    Map<String, dynamic>? arguments,
  }) async {
    if (route == null) {
      throw Exception('Route name is required for push operation');
    }
    // Intentionally not awaited: pushNamed completes only on pop.
    unawaited(_requireNavigator().pushNamed<Object?>(route, arguments: arguments));
  }

  /// Pops the current route from the navigator.
  ///
  /// Returns [result] if provided.
  Future<void> pop([dynamic result]) async {
    final navigator = _requireNavigator();
    if (navigator.canPop()) {
      navigator.pop(result);
    } else {
      throw Exception('Cannot pop: no routes to pop');
    }
  }

  /// Replaces the current route with a new named route.
  Future<void> pushReplacement({
    String? route,
    Map<String, dynamic>? arguments,
  }) async {
    if (route == null) {
      throw Exception('Route name is required for pushReplacement operation');
    }
    // Intentionally not awaited — see [push] for rationale.
    unawaited(
      _requireNavigator()
          .pushReplacementNamed<Object?, Object?>(route, arguments: arguments),
    );
  }

  /// Pops routes until a route with the given [routeName] is found.
  ///
  /// If [routeName] is null, pops until the root route.
  Future<void> popUntil(String? routeName) async {
    final navigator = _requireNavigator();
    if (routeName != null) {
      navigator.popUntil((route) => route.settings.name == routeName);
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  /// Gets information about the current navigation stack.
  Map<String, dynamic> getNavigationStack() {
    final navigator = _findRootNavigator();
    if (navigator == null) {
      return {
        'status': 'Error',
        'error': 'No Navigator found in the widget tree',
      };
    }
    return {
      'status': 'Success',
      'canPop': navigator.canPop(),
      'message': 'Navigation stack information retrieved',
    };
  }
}
