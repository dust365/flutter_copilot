import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// Service for controlling Flutter app navigation through VM service extensions.
class NavigationService {
  /// Gets the BuildContext from the root element.
  BuildContext? get context {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) {
      return null;
    }
    return rootElement;
  }

  /// Pushes a new route onto the navigator.
  ///
  /// If [route] is provided, uses named route. Otherwise creates a MaterialPageRoute.
  /// [arguments] are passed to the route.
  Future<void> push({
    String? route,
    Map<String, dynamic>? arguments,
  }) async {
    final ctx = context;
    if (ctx == null) {
      throw Exception('No BuildContext available. App may not be initialized.');
    }

    final navigator = Navigator.of(ctx, rootNavigator: true);

    if (route != null) {
      await navigator.pushNamed(route, arguments: arguments);
    } else {
      throw Exception('Route name is required for push operation');
    }
  }

  /// Pops the current route from the navigator.
  ///
  /// Returns [result] if provided.
  Future<void> pop([dynamic result]) async {
    final ctx = context;
    if (ctx == null) {
      throw Exception('No BuildContext available. App may not be initialized.');
    }

    final navigator = Navigator.of(ctx, rootNavigator: true);

    if (navigator.canPop()) {
      navigator.pop(result);
    } else {
      throw Exception('Cannot pop: no routes to pop');
    }
  }

  /// Replaces the current route with a new route.
  ///
  /// If [route] is provided, uses named route. Otherwise creates a MaterialPageRoute.
  /// [arguments] are passed to the route.
  Future<void> pushReplacement({
    String? route,
    Map<String, dynamic>? arguments,
  }) async {
    final ctx = context;
    if (ctx == null) {
      throw Exception('No BuildContext available. App may not be initialized.');
    }

    final navigator = Navigator.of(ctx, rootNavigator: true);

    if (route != null) {
      await navigator.pushReplacementNamed(route, arguments: arguments);
    } else {
      throw Exception('Route name is required for pushReplacement operation');
    }
  }

  /// Pops routes until a route with the given [routeName] is found.
  ///
  /// If [routeName] is null, pops until the root route.
  Future<void> popUntil(String? routeName) async {
    final ctx = context;
    if (ctx == null) {
      throw Exception('No BuildContext available. App may not be initialized.');
    }

    final navigator = Navigator.of(ctx, rootNavigator: true);

    if (routeName != null) {
      navigator.popUntil((route) {
        return route.settings.name == routeName;
      });
    } else {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  /// Gets information about the current navigation stack.
  Map<String, dynamic> getNavigationStack() {
    final ctx = context;
    if (ctx == null) {
      return {
        'status': 'Error',
        'error': 'No BuildContext available',
      };
    }

    final navigator = Navigator.of(ctx, rootNavigator: true);

    // Note: Navigator doesn't expose route stack directly in a simple way
    // This is a simplified implementation
    return {
      'status': 'Success',
      'canPop': navigator.canPop(),
      'message': 'Navigation stack information retrieved',
    };
  }
}
