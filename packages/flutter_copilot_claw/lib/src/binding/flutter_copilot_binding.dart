import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_copilot_claw/src/binding/copilot_build_owner.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/element_tree_finder.dart';
import 'package:flutter_copilot_claw/src/services/gesture_dispatcher.dart';
import 'package:flutter_copilot_claw/src/services/log_collector.dart';
import 'package:flutter_copilot_claw/src/services/navigation_service.dart';
import 'package:flutter_copilot_claw/src/services/screenshot_service.dart';
import 'package:flutter_copilot_claw/src/services/scroll_simulator.dart';
import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';
import 'package:flutter_copilot_claw/src/services/text_input_simulator.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/widgets/tap_feedback_overlay.dart';
import 'package:flutter_copilot_claw/src/services/widget_rebuild_tracker.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

/// A custom binding that extends Flutter's default binding to provide
/// integration points for the Flutter Copilot MCP.
///
/// **Usage**: Call [ensureInitialized] as a **drop-in replacement** for
/// `WidgetsFlutterBinding.ensureInitialized()` at the very start of `main()`:
///
/// ```dart
/// void main() async {
///   // Use FlutterCopilotBinding instead of WidgetsFlutterBinding
///   FlutterCopilotBinding.ensureInitialized();
///   await setupSystemUI();
///   await SomeInitializer.init();
///   runApp(const MyApp());
/// }
/// ```
///
/// Or use [runAppWithConfig] for automatic log/error zone capture:
///
/// ```dart
/// void main() {
///   FlutterCopilotBinding.runAppWithConfig(const MyApp());
/// }
/// ```
///
/// **Important**: Do NOT call `WidgetsFlutterBinding.ensureInitialized()`
/// before [ensureInitialized] or [runAppWithConfig] — it will cause a
/// "Binding already initialized" error. [FlutterCopilotBinding] is a
/// subclass of [WidgetsFlutterBinding] and provides the same functionality.
class FlutterCopilotBinding extends WidgetsFlutterBinding {
  /// Creates and initializes the binding with the given configuration.
  ///
  /// This is a **drop-in replacement** for `WidgetsFlutterBinding.ensureInitialized()`.
  /// Call this at the very start of `main()` instead of
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  ///
  /// Returns the singleton instance of [FlutterCopilotBinding].
  static FlutterCopilotBinding ensureInitialized([
    FlutterCopilotConfiguration configuration =
        const FlutterCopilotConfiguration(),
  ]) {
    if (_instance != null) return instance;

    try {
      FlutterCopilotBinding._(configuration);
    } on Object {
      // If binding creation failed, it's likely because another binding
      // (e.g. WidgetsFlutterBinding) was already initialized.
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('FlutterCopilotBinding initialization failed.'),
        ErrorDescription(
          'This usually happens because WidgetsFlutterBinding.ensureInitialized() '
          'was called before FlutterCopilotBinding.ensureInitialized().\n\n'
          'FlutterCopilotBinding is a drop-in replacement for WidgetsFlutterBinding '
          'and provides the same functionality.\n',
        ),
        ErrorHint(
          'Fix: Replace WidgetsFlutterBinding.ensureInitialized() with '
          'FlutterCopilotBinding.ensureInitialized() at the start of main().\n\n'
          '  // Before (causes error):\n'
          '  WidgetsFlutterBinding.ensureInitialized();\n'
          '  FlutterCopilotBinding.ensureInitialized(); // ERROR!\n\n'
          '  // After (correct):\n'
          '  FlutterCopilotBinding.ensureInitialized();\n'
          '  // ... your setup code ...\n'
          '  runApp(const MyApp());\n',
        ),
      ]);
    }
    return instance;
  }

  /// The singleton instance of [FlutterCopilotBinding].
  static FlutterCopilotBinding get instance =>
      BindingBase.checkInstance(_instance);
  static FlutterCopilotBinding? _instance;

  FlutterCopilotBinding._(this.configuration);

  /// Configuration for the Flutter Copilot extensions.
  final FlutterCopilotConfiguration configuration;

  BuildOwner? _defaultBuildOwner;
  CopilotBuildOwner? _copilotBuildOwner;
  TapFeedbackController? _tapFeedbackController;
  OverlayEntry? _tapFeedbackOverlayEntry;

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
    if (configuration.showTapFeedback) {
      _tapFeedbackController = TapFeedbackController();
      _gestureDispatcher = GestureDispatcher(
        onTapAt: (Offset offset) => _tapFeedbackController!.showAt(offset),
      );
    } else {
      _gestureDispatcher = GestureDispatcher();
    }
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

    _defaultBuildOwner = super.buildOwner;
    if (configuration.enableGlobalRebuildHook) {
      enableGlobalRebuildHook();
    }

    // Auto-inject tap feedback overlay after the first frame
    if (configuration.showTapFeedback && _tapFeedbackController != null) {
      _scheduleTapFeedbackInjection();
    }
  }

  @override
  BuildOwner get buildOwner {
    if (_copilotBuildOwner != null) return _copilotBuildOwner!;
    if (_defaultBuildOwner != null) return _defaultBuildOwner!;
    return super.buildOwner!;
  }

  /// The tap feedback controller, if [FlutterCopilotConfiguration.showTapFeedback] was true.
  /// Used by [TapFeedbackOverlay] to show a red dot at the last MCP tap position.
  TapFeedbackController? get tapFeedbackController => _tapFeedbackController;

  // ---------- Tap feedback overlay auto-injection ----------

  /// Schedules injection of the tap feedback overlay into the app's [Overlay]
  /// after the first frame is drawn (when the Navigator/Overlay are available).
  void _scheduleTapFeedbackInjection() {
    addPostFrameCallback((_) => _tryInjectTapFeedbackOverlay());
  }

  /// Finds the root [OverlayState] and inserts a [TapFeedbackOverlay] via
  /// [OverlayEntry]. Retries on the next frame if the overlay is not yet
  /// available (e.g. first frame not drawn yet).
  void _tryInjectTapFeedbackOverlay() {
    if (_tapFeedbackOverlayEntry != null || _tapFeedbackController == null) {
      return;
    }

    final overlayState = _findOverlayState();
    if (overlayState != null && overlayState.mounted) {
      _tapFeedbackOverlayEntry = OverlayEntry(
        builder: (_) => TapFeedbackOverlay(controller: _tapFeedbackController!),
      );
      overlayState.insert(_tapFeedbackOverlayEntry!);
    } else {
      // Overlay not available yet, retry after the next frame.
      addPostFrameCallback((_) => _tryInjectTapFeedbackOverlay());
    }
  }

  /// Walks the element tree to find the first [OverlayState] (typically the
  /// root Navigator's overlay).
  OverlayState? _findOverlayState() {
    OverlayState? result;
    void visitor(Element element) {
      if (result != null) return;
      if (element is StatefulElement && element.state is OverlayState) {
        result = element.state as OverlayState;
        return;
      }
      element.visitChildren(visitor);
    }

    rootElement?.visitChildren(visitor);
    return result;
  }

  /// Enables global rebuild tracking for widget repaint monitoring.
  ///
  /// Called during [initInstances] only when [FlutterCopilotConfiguration.enableGlobalRebuildHook]
  /// is true. On non-Web platforms, creates [CopilotBuildOwner] that reuses the original
  /// [BuildOwner]'s [FocusManager] (via getter override) while passing a no-op FocusManager to the
  /// super constructor to avoid the double-registration assertion. On Web, creating a second
  /// [BuildOwner] has additional issues, so we only initialize the tracker (snapshot stays empty).
  @protected
  void enableGlobalRebuildHook() {
    WidgetRebuildTracker.ensureInitialized();
    // super.buildOwner is the default BuildOwner created by WidgetsBinding.initInstances().
    // Its FocusManager has already registered global handlers. We reuse it.
    final originalBuildOwner = super.buildOwner!;
    _copilotBuildOwner = CopilotBuildOwner(
      onBuildScheduled: SchedulerBinding.instance.ensureVisualUpdate,
      realFocusManager: originalBuildOwner.focusManager,
    );
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
    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
      _logCollector.addConsoleLog('Uncaught error: $error\n$stackTrace',
          isError: true);
      return previousOnError?.call(error, stackTrace) ?? false;
    };
  }

  /// Runs the app with optional [configuration], and Zone-based capture of [print] and zone uncaught errors.
  /// Prefer this so [getLogs] includes print() and async errors. Add custom logs with [addLog].
  ///
  /// **用法一（最简单）**: 不需要在 main() 中做 async 初始化：
  /// ```dart
  /// void main() {
  ///   FlutterCopilotBinding.runAppWithConfig(const MyApp());
  /// }
  /// ```
  ///
  /// **用法二**: 需要先做 async 初始化（如 setupSystemUI、插件初始化等）：
  /// ```dart
  /// void main() async {
  ///   FlutterCopilotBinding.ensureInitialized();
  ///   await setupSystemUI();
  ///   await SomeInitializer.init();
  ///   FlutterCopilotBinding.runAppWithConfig(const MyApp());
  /// }
  /// ```
  ///
  /// **注意**: 不要在调用本方法前调用 `WidgetsFlutterBinding.ensureInitialized()`。
  /// 如需提前初始化 binding，请改用 `FlutterCopilotBinding.ensureInitialized()`。
  static void runAppWithConfig(Widget app,
      [FlutterCopilotConfiguration? configuration]) {
    runZonedGuarded(
      () {
        ensureInitialized(configuration ?? const FlutterCopilotConfiguration());
        runApp(app);
      },
      (Object error, StackTrace stack) {
        LogCollector.addConsoleLogStatic('Uncaught error: $error\n$stack',
            isError: true);
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
            'message':
                'Entered text into element matching: ${matcher.toJson()}',
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
          final direction = params['direction'] is String
              ? params['direction'] as String
              : null;
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
            'message':
                'Swiped element matching: ${matcher.toJson()} in direction: $direction',
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
          // VM service extension params arrive as Map<String, String>, so a
          // raw `as num?` cast throws a TypeError for any caller-supplied
          // value. Reuse _parseDouble to accept both num and numeric strings.
          final durationMs = _parseDouble(params['duration'])?.toInt() ?? 500;
          final duration = Duration(milliseconds: durationMs);

          await _gestureDispatcher.longPress(
            matcher,
            duration,
            _widgetFinder,
            configuration,
          );

          return <String, dynamic>{
            'status': 'Success',
            'message':
                'Long pressed element matching: ${matcher.toJson()} for ${durationMs}ms',
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
          await _gestureDispatcher.doubleTap(
              matcher, _widgetFinder, configuration);

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

          final route =
              params['route'] is String ? params['route'] as String : null;
          // VM service params are Map<String, String>: nested maps arrive as
          // JSON strings rather than Maps, so the previous `is Map` check was
          // always false and `arguments` was silently dropped. Parse it back.
          final arguments = _parseArguments(params['arguments']);

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
                'error':
                    'Invalid action: $action. Must be push, pop, replace, or popUntil',
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

    // Extension: Rebuild snapshot (for repaint monitoring)
    registerServiceExtension(
      name: 'flutter_copilot.rebuild.snapshot',
      callback: (params) async {
        try {
          final tracker = WidgetRebuildTracker.instance;
          if (tracker == null) {
            return <String, dynamic>{
              'status': 'Success',
              'enabled': false,
              'message':
                  'Rebuild tracking not enabled (enableGlobalRebuildHook is false)',
            };
          }
          final topLimit = params['topLimit'] is int
              ? params['topLimit'] as int
              : (params['topLimit'] is String
                      ? int.tryParse(params['topLimit'] as String)
                      : null) ??
                  20;
          final snapshot = tracker.getSnapshot(topLimit: topLimit);
          return <String, dynamic>{
            'status': 'Success',
            'enabled': true,
            ...snapshot,
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

  /// Parses a nested map argument that may have been stringified by the VM
  /// service extension transport.
  ///
  /// Accepts three shapes:
  ///   - `null` → returns null
  ///   - `Map<String, dynamic>` (direct call) → returned as-is
  ///   - JSON-encoded String (VM service extension transport) → decoded
  ///
  /// Returns null for anything else, or if decoding fails / does not yield
  /// an object.
  static Map<String, dynamic>? _parseArguments(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      if (value.isEmpty) return null;
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
