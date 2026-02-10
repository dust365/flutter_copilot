import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/element_tree_finder.dart';
import 'package:flutter_copilot_claw/src/services/gesture_dispatcher.dart';
import 'package:flutter_copilot_claw/src/services/log_collector.dart';
import 'package:flutter_copilot_claw/src/services/navigation_service.dart';
import 'package:flutter_copilot_claw/src/services/screenshot_service.dart';
import 'package:flutter_copilot_claw/src/services/scroll_simulator.dart';
import 'package:flutter_copilot_claw/src/services/text_input_simulator.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

/// A custom binding that extends Flutter's default binding to provide
/// integration points for the Flutter Copilot MCP.
class FlutterCopilotBinding extends WidgetsFlutterBinding {
  /// Creates and initializes the binding with the given configuration.
  ///
  /// Returns the singleton instance of [FlutterCopilotBinding].
  static FlutterCopilotBinding ensureInitialized([
    FlutterCopilotConfiguration configuration = const FlutterCopilotConfiguration(),
  ]) {
    if (_instance == null) {
      FlutterCopilotBinding._(configuration);
    }
    return instance;
  }

  /// The singleton instance of [FlutterCopilotBinding].
  static FlutterCopilotBinding get instance => BindingBase.checkInstance(_instance);
  static FlutterCopilotBinding? _instance;

  FlutterCopilotBinding._(this.configuration);

  /// Configuration for the Flutter Copilot extensions.
  final FlutterCopilotConfiguration configuration;

  // Service instances
  late final ElementTreeFinder _elementTreeFinder;
  late final GestureDispatcher _gestureDispatcher;
  late final LogCollector _logCollector;
  late final NavigationService _navigationService;
  late final ScreenshotService _screenshotService;
  late final ScrollSimulator _scrollSimulator;
  late final TextInputSimulator _textInputSimulator;
  late final WidgetFinder _widgetFinder;

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;

    // Initialize services
    _widgetFinder = WidgetFinder();
    _elementTreeFinder = ElementTreeFinder(configuration);
    _gestureDispatcher = GestureDispatcher();
    _logCollector = LogCollector();
    _navigationService = NavigationService();
    _screenshotService = ScreenshotService(
      maxScreenshotSize: configuration.maxScreenshotSize,
    );
    _scrollSimulator = ScrollSimulator(_gestureDispatcher, _widgetFinder);
    _textInputSimulator = TextInputSimulator(_widgetFinder);

    // Initialize log collection and register log/error monitors inside the binding
    _logCollector.initialize();
    _registerLogMonitors();
  }

  /// Registers error monitors (FlutterError, PlatformDispatcher.onError).
  /// For print() and zone errors use [runAppWithConfig]. For custom logs use [addLog].
  void _registerLogMonitors() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final buffer = StringBuffer()..write(details.exceptionAsString());
      if (details.stack != null) {
        buffer.write('\n${details.stack}');
      }
      _logCollector.addConsoleLog(buffer.toString(), isError: true);
      previousFlutterError?.call(details);
    };

    final previousOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stackTrace) {
      _logCollector.addConsoleLog('Uncaught error: $error\n$stackTrace', isError: true);
      return previousOnError?.call(error, stackTrace) ?? false;
    };
  }

  /// Runs the app with optional [configuration], and Zone-based capture of [print] and zone uncaught errors.
  /// Prefer this so [getLogs] includes print() and async errors. Add custom logs with [addLog].
  ///
  /// **Zone 要求**：binding 与 runApp 必须在同一 Zone。因此使用本方法时请**不要**在
  /// 外部先调用 [ensureInitialized]；本方法会在同一 Zone 内先执行 [ensureInitialized] 再 runApp。
  static void runAppWithConfig(Widget app, [FlutterCopilotConfiguration? configuration]) {
    runZonedGuarded(
      () {
        ensureInitialized(configuration ?? const FlutterCopilotConfiguration());
        runApp(app);
      },
      (Object error, StackTrace stack) {
        LogCollector.addConsoleLogStatic('Uncaught error: $error\n$stack', isError: true);
        // ignore: avoid_print
        print('Uncaught error: $error\n$stack');
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          LogCollector.addConsoleLogStatic(line);
          parent.print(zone, line);
        },
      ),
    );
  }

  /// Adds a custom log entry to the collector (included in [getLogs]).
  /// Call after [ensureInitialized]. Use for app-specific messages.
  static void addLog(String message, {bool isError = false}) {
    LogCollector.addConsoleLogStatic(message, isError: isError);
  }

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();

    // Extension: Get interactive elements tree
    registerServiceExtension(
      name: 'flutter_copilot.interactiveElements',
      callback: (params) async {
        try {
          final elements = _elementTreeFinder.findInteractiveElements();
          return <String, dynamic>{'status': 'Success', 'elements': elements};
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Tap element by matcher
    registerServiceExtension(
      name: 'flutter_copilot.tap',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          await _gestureDispatcher.tap(matcher, _widgetFinder, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Tapped element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Enter text into a text field
    registerServiceExtension(
      name: 'flutter_copilot.enterText',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          final input = params['input'];

          if (input == null) {
            return <String, dynamic>{
              'status': 'Error',
              'error': 'Missing required parameter: input',
            };
          }

          await _textInputSimulator.enterText(matcher, input, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Entered text into element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Scroll until widget is visible
    registerServiceExtension(
      name: 'flutter_copilot.scrollTo',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);

          await _scrollSimulator.scrollUntilVisible(matcher, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Scrolled to element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Get logs
    registerServiceExtension(
      name: 'flutter_copilot.getLogs',
      callback: (params) async {
        try {
          final logs = _logCollector.getFormattedLogs();

          return <String, dynamic>{
            'status': 'Success',
            'logs': logs,
            'count': logs.length,
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Take screenshots
    registerServiceExtension(
      name: 'flutter_copilot.takeScreenshots',
      callback: (params) async {
        try {
          final screenshots = await _screenshotService.takeScreenshots();

          return <String, dynamic>{
            'status': 'Success',
            'screenshots': screenshots,
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Drag element
    registerServiceExtension(
      name: 'flutter_copilot.drag',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);

          // Parse deltaX/deltaY with type conversion
          final deltaX = _parseDouble(params['deltaX']) ?? 0.0;
          final deltaY = _parseDouble(params['deltaY']) ?? 0.0;

          // Support from/to coordinates as alternative
          Offset? from;
          Offset? to;
          if (params.containsKey('fromX') && params.containsKey('fromY')) {
            final fromX = _parseDouble(params['fromX']) ?? 0.0;
            final fromY = _parseDouble(params['fromY']) ?? 0.0;
            from = Offset(fromX, fromY);
          }
          if (params.containsKey('toX') && params.containsKey('toY')) {
            final toX = _parseDouble(params['toX']) ?? 0.0;
            final toY = _parseDouble(params['toY']) ?? 0.0;
            to = Offset(toX, toY);
          }

          if (from != null && to != null) {
            await _gestureDispatcher.drag(from, to);
          } else {
            await _gestureDispatcher.dragByMatcher(
              matcher,
              deltaX,
              deltaY,
              _widgetFinder,
              configuration,
            );
          }

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Dragged element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Swipe element
    registerServiceExtension(
      name: 'flutter_copilot.swipe',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          final direction = params['direction'] is String ? params['direction'] as String : null;
          final distance = _parseDouble(params['distance']) ?? 200.0;

          if (direction == null) {
            return <String, dynamic>{
              'status': 'Error',
              'error': 'Missing required parameter: direction',
            };
          }

          await _gestureDispatcher.swipe(
            matcher,
            direction,
            distance,
            _widgetFinder,
            configuration,
          );

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Swiped element matching: ${matcher.toJson()} in direction: $direction',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Long press element
    registerServiceExtension(
      name: 'flutter_copilot.longPress',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          final durationMs = (params['duration'] as num?)?.toInt() ?? 500;
          final duration = Duration(milliseconds: durationMs);

          await _gestureDispatcher.longPress(
            matcher,
            duration,
            _widgetFinder,
            configuration,
          );

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Long pressed element matching: ${matcher.toJson()} for ${durationMs}ms',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Double tap element
    registerServiceExtension(
      name: 'flutter_copilot.doubleTap',
      callback: (params) async {
        try {
          final matcher = WidgetMatcher.fromJson(params);
          await _gestureDispatcher.doubleTap(matcher, _widgetFinder, configuration);

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Double tapped element matching: ${matcher.toJson()}',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );

    // Extension: Navigate
    registerServiceExtension(
      name: 'flutter_copilot.navigate',
      callback: (params) async {
        try {
          final action = params['action'];
          if (action is! String) {
            return <String, dynamic>{
              'status': 'Error',
              'error': 'Missing required parameter: action',
            };
          }

          final route = params['route'] is String ? params['route'] as String : null;
          final arguments = params['arguments'] is Map<String, dynamic>
              ? params['arguments'] as Map<String, dynamic>
              : null;

          switch (action.toLowerCase()) {
            case 'push':
              await _navigationService.push(route: route, arguments: arguments);
              break;
            case 'pop':
              await _navigationService.pop();
              break;
            case 'replace':
            case 'pushreplacement':
              await _navigationService.pushReplacement(
                route: route,
                arguments: arguments,
              );
              break;
            case 'popuntil':
              await _navigationService.popUntil(route);
              break;
            default:
              return <String, dynamic>{
                'status': 'Error',
                'error': 'Invalid action: $action. Must be push, pop, replace, or popUntil',
              };
          }

          return <String, dynamic>{
            'status': 'Success',
            'message': 'Navigation action "$action" completed successfully',
          };
        } catch (err, st) {
          return <String, dynamic>{
            'status': 'Error',
            'error': err.toString(),
            'stackTrace': st.toString(),
          };
        }
      },
    );
  }

  @override
  Future<void> reassembleApplication() {
    _logCollector.clear();
    return super.reassembleApplication();
  }

  /// Parses a value to double, handling both num and String types.
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
