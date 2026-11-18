import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/tap_feedback_controller.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

/// Global hit point and, when a widget was matched, its global bounds.
class _ResolvedTarget {
  const _ResolvedTarget(this.position, this.bounds);

  final Offset position;
  final Rect? bounds;
}

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  GestureDispatcher({this.onTapAt, this.onDragPath, this.routeEpoch});

  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

  /// Called when a tap, long press, or double tap is shown and, when the route
  /// did not change, again when the pointer events finish.
  ///
  /// [bounds] is the matched widget in global coordinates, or null when the
  /// gesture targeted raw coordinates.
  final void Function(Offset position, Rect? bounds, TapFeedbackKind kind)?
      onTapAt;

  /// Called with the global polyline of a drag or swipe, including the start.
  ///
  /// Invoked before the pointer events and, when the route did not change,
  /// again after them.
  final void Function(List<Offset> path)? onDragPath;

  /// Route generation while a gesture is in flight.
  ///
  /// The mark is shown again after the pointer events only when this value is
  /// unchanged. A page change clears the mark and must not draw it back on the
  /// next page.
  final int Function()? routeEpoch;

  int? _shownOnRoute() => routeEpoch?.call();

  bool _routeUnchanged(int? epoch) =>
      routeEpoch == null || routeEpoch!.call() == epoch;

  int _nextPointerId = 1;

  /// Simulates a tap on an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], taps directly at the specified
  /// coordinates without searching the widget tree (fast path).
  Future<void> tap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    final _ResolvedTarget target = _resolveTarget(
      matcher,
      widgetFinder,
      configuration,
    );
    await _dispatchTapAtPosition(
      target.position,
      target.bounds,
      TapFeedbackKind.tap,
    );
  }

  /// Delay between showing tap feedback and dispatching the actual pointer events (ms).
  static const int kTapFeedbackDelayMs = 300;

  Future<void> _dispatchTapAtPosition(
    Offset globalPosition,
    Rect? bounds,
    TapFeedbackKind kind,
  ) async {
    final int pointerId = _nextPointerId++;

    // Show feedback first, then wait before executing the tap.
    final int? epoch = _shownOnRoute();
    onTapAt?.call(globalPosition, bounds, kind);
    await Future<void>.delayed(
      const Duration(milliseconds: kTapFeedbackDelayMs),
    );

    final List<List<PointerEvent>> records = [
      [
        PointerAddedEvent(position: globalPosition),
        PointerDownEvent(pointer: pointerId, position: globalPosition),
      ],
      [PointerUpEvent(pointer: pointerId, position: globalPosition)],
    ];

    await _handlePointerEventRecord(records);
    if (_routeUnchanged(epoch)) {
      onTapAt?.call(globalPosition, bounds, kind);
    }
  }

  /// Simulates a drag gesture from [from] to [to].
  ///
  /// [feedback] controls whether to draw the arrow for this gesture.
  Future<void> drag(Offset from, Offset to, {bool feedback = true}) async {
    final List<Offset> path = _samplePath(from, to, maxDelta: kMaxDelta);
    await _dispatchDrag(path, stepDelay: kDelay, feedback: feedback);
  }

  /// Simulates a drag gesture starting from an element that matches the given [matcher].
  ///
  /// If [matcher] is a [CoordinatesMatcher], uses the specified coordinates as the start position.
  /// Otherwise, finds the element and uses its center as the start position.
  /// The drag moves by [deltaX] and [deltaY] pixels from the start position.
  Future<void> dragByMatcher(
    WidgetMatcher matcher,
    double deltaX,
    double deltaY,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    final _ResolvedTarget target = _resolveTarget(
      matcher,
      widgetFinder,
      configuration,
    );
    final Offset endPosition = target.position + Offset(deltaX, deltaY);
    await drag(target.position, endPosition);
  }

  /// Simulates a swipe gesture on an element that matches the given [matcher].
  ///
  /// [direction] should be one of: 'left', 'right', 'up', 'down'
  /// [distance] is the swipe distance in pixels (default: 200)
  Future<void> swipe(
    WidgetMatcher matcher,
    String direction,
    double distance,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    final _ResolvedTarget target = _resolveTarget(
      matcher,
      widgetFinder,
      configuration,
    );

    final Offset endPosition = switch (direction.toLowerCase()) {
      'left' => target.position + Offset(-distance, 0),
      'right' => target.position + Offset(distance, 0),
      'up' => target.position + Offset(0, -distance),
      'down' => target.position + Offset(0, distance),
      _ => throw Exception(
          'Invalid swipe direction: $direction. Must be left, right, up, or down',
        ),
    };

    final List<Offset> path = _samplePath(
      target.position,
      endPosition,
      maxDelta: kMaxDelta * 2,
      maxSteps: 20,
    );
    await _dispatchDrag(path, stepDelay: const Duration(milliseconds: 5));
  }

  /// Simulates a long press gesture on an element that matches the given [matcher].
  ///
  /// [duration] is how long to hold the press (default: 500ms).
  /// If [matcher] is a [CoordinatesMatcher], uses the specified coordinates.
  /// Otherwise, finds the element and uses its center position.
  Future<void> longPress(
    WidgetMatcher matcher,
    Duration duration,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    final _ResolvedTarget target = _resolveTarget(
      matcher,
      widgetFinder,
      configuration,
    );
    await _dispatchLongPressAtPosition(
      target.position,
      target.bounds,
      duration,
    );
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Rect? bounds,
    Duration duration,
  ) async {
    final int? epoch = _shownOnRoute();
    onTapAt?.call(globalPosition, bounds, TapFeedbackKind.longPress);
    await Future<void>.delayed(
      const Duration(milliseconds: kTapFeedbackDelayMs),
    );

    final int pointerId = _nextPointerId++;

    final List<List<PointerEvent>> records = [
      [
        PointerAddedEvent(position: globalPosition),
        PointerDownEvent(pointer: pointerId, position: globalPosition),
      ],
      [
        PointerMoveEvent(
          pointer: pointerId,
          position: globalPosition + const Offset(0.5, 0.5),
          delta: const Offset(0.5, 0.5),
        ),
      ],
      [PointerUpEvent(pointer: pointerId, position: globalPosition)],
    ];

    records[0].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);

    records[1].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);

    final Duration holdDuration = duration - (kDelay * 2);
    if (holdDuration > Duration.zero) {
      await Future<void>.delayed(holdDuration);
    }

    records[2].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);
    if (_routeUnchanged(epoch)) {
      onTapAt?.call(globalPosition, bounds, TapFeedbackKind.longPress);
    }
  }

  /// Simulates a double tap on an element that matches the given [matcher].
  ///
  /// Performs two taps with a short interval (200ms) between them at the same position.
  Future<void> doubleTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    final _ResolvedTarget target = _resolveTarget(
      matcher,
      widgetFinder,
      configuration,
    );

    await _dispatchTapAtPosition(
      target.position,
      target.bounds,
      TapFeedbackKind.doubleTap,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _dispatchTapAtPosition(
      target.position,
      target.bounds,
      TapFeedbackKind.doubleTap,
    );
  }

  Future<void> _dispatchDrag(
    List<Offset> path, {
    required Duration stepDelay,
    bool feedback = true,
  }) async {
    final int? epoch = feedback ? _shownOnRoute() : null;
    if (feedback) {
      onDragPath?.call(path);
    }

    final int pointerId = _nextPointerId++;
    final List<List<PointerEvent>> records = <List<PointerEvent>>[
      [
        PointerAddedEvent(position: path.first),
        PointerDownEvent(pointer: pointerId, position: path.first),
      ],
      for (var i = 1; i < path.length; i++)
        [
          PointerMoveEvent(
            pointer: pointerId,
            position: path[i],
            delta: path[i] - path[i - 1],
          ),
        ],
      [PointerUpEvent(pointer: pointerId, position: path.last)],
    ];

    for (final List<PointerEvent> record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(stepDelay);
    }
    if (feedback && _routeUnchanged(epoch)) {
      onDragPath?.call(path);
    }
  }

  /// Straight polyline from [from] to [to].
  ///
  /// Steps are at most [maxDelta] logical pixels. [maxSteps] caps the count
  /// used by swipes.
  List<Offset> _samplePath(
    Offset from,
    Offset to, {
    required double maxDelta,
    int? maxSteps,
  }) {
    final double distance = (to - from).distance;
    var stepCount = (distance / maxDelta).ceil();
    if (stepCount < 1) {
      stepCount = 1;
    }
    if (maxSteps != null && stepCount > maxSteps) {
      stepCount = maxSteps;
    }
    return <Offset>[
      from,
      for (var i = 1; i <= stepCount; i++)
        Offset.lerp(from, to, i / stepCount)!,
    ];
  }

  _ResolvedTarget _resolveTarget(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) {
    if (matcher is CoordinatesMatcher) {
      return _ResolvedTarget(matcher.offset, null);
    }

    final Element? element = widgetFinder.findElement(matcher, configuration);
    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    }

    final RenderObject? renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }
    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    final RenderBox box = _visibleBox(element, renderObject);
    final Offset center = box.size.center(Offset.zero);
    final Offset position = box.localToGlobal(center);
    final Rect bounds = Rect.fromPoints(
      box.localToGlobal(Offset.zero),
      box.localToGlobal(box.size.bottomRight(Offset.zero)),
    );
    return _ResolvedTarget(position, bounds);
  }

  /// Drops a margin [RenderPadding] introduced by a widget such as [Container].
  ///
  /// A [Padding] the caller matched directly keeps its own box.
  RenderBox _visibleBox(Element element, RenderBox renderObject) {
    if (renderObject is! RenderPadding || element is RenderObjectElement) {
      return renderObject;
    }
    final RenderBox? child = renderObject.child;
    if (child != null && child.hasSize) {
      return child;
    }
    return renderObject;
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final List<PointerEvent> record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }
}
