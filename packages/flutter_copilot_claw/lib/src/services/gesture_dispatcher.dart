import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_copilot_claw/src/binding/flutter_copilot_configuration.dart';
import 'package:flutter_copilot_claw/src/services/widget_finder.dart';
import 'package:flutter_copilot_claw/src/services/widget_matcher.dart';

/// Dispatches gesture events to simulate user interactions.
class GestureDispatcher {
  static const kMaxDelta = 40.0;
  static const kDelay = Duration(milliseconds: 10);

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
    // Fast path for coordinate-based tapping
    if (matcher is CoordinatesMatcher) {
      await _dispatchTapAtPosition(matcher.offset);
      return;
    }

    final element = widgetFinder.findElement(matcher, configuration);

    if (element == null) {
      throw Exception('Element matching ${matcher.toJson()} not found');
    } else {
      await _dispatchTapAtElement(element);
    }
  }

  Future<void> _dispatchTapAtElement(Element element) async {
    final renderObject = element.renderObject;

    if (renderObject is! RenderBox) {
      throw Exception('Element does not have a RenderBox');
    }

    if (!renderObject.hasSize) {
      throw Exception('RenderBox does not have a size yet');
    }

    // Get the center position of the widget
    final center = renderObject.size.center(Offset.zero);
    final globalPosition = renderObject.localToGlobal(center);

    await _dispatchTapAtPosition(globalPosition);
  }

  Future<void> _dispatchTapAtPosition(Offset globalPosition) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down immediately
      [
        PointerAddedEvent(position: globalPosition),
        PointerDownEvent(pointer: pointerId, position: globalPosition),
      ],
      // Pointer up after a short delay
      [PointerUpEvent(pointer: pointerId, position: globalPosition)],
    ];

    await _handlePointerEventRecord(records);
  }

  /// Simulates a drag gesture from [from] to [to].
  Future<void> drag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    final stepCount =
        (distance / kMaxDelta).ceil().clamp(1, double.infinity).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: position,
          delta: stepDelta,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: from),
        PointerDownEvent(pointer: pointerId, position: from),
      ],
      ...moveRecords,
      [PointerUpEvent(pointer: pointerId, position: to)],
    ];

    await _handlePointerEventRecord(records);
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
    Offset startPosition;

    // Fast path for coordinate-based dragging
    if (matcher is CoordinatesMatcher) {
      startPosition = matcher.offset;
    } else {
      final element = widgetFinder.findElement(matcher, configuration);
      if (element == null) {
        throw Exception('Element matching ${matcher.toJson()} not found');
      }

      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Element does not have a RenderBox');
      }

      if (!renderObject.hasSize) {
        throw Exception('RenderBox does not have a size yet');
      }

      // Get the center position of the widget
      final center = renderObject.size.center(Offset.zero);
      startPosition = renderObject.localToGlobal(center);
    }

    final endPosition = startPosition + Offset(deltaX, deltaY);
    await drag(startPosition, endPosition);
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
    Offset startPosition;

    // Fast path for coordinate-based swiping
    if (matcher is CoordinatesMatcher) {
      startPosition = matcher.offset;
    } else {
      final element = widgetFinder.findElement(matcher, configuration);
      if (element == null) {
        throw Exception('Element matching ${matcher.toJson()} not found');
      }

      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Element does not have a RenderBox');
      }

      if (!renderObject.hasSize) {
        throw Exception('RenderBox does not have a size yet');
      }

      // Get the center position of the widget
      final center = renderObject.size.center(Offset.zero);
      startPosition = renderObject.localToGlobal(center);
    }

    Offset endPosition;
    switch (direction.toLowerCase()) {
      case 'left':
        endPosition = startPosition + Offset(-distance, 0);
        break;
      case 'right':
        endPosition = startPosition + Offset(distance, 0);
        break;
      case 'up':
        endPosition = startPosition + Offset(0, -distance);
        break;
      case 'down':
        endPosition = startPosition + Offset(0, distance);
        break;
      default:
        throw Exception(
            'Invalid swipe direction: $direction. Must be left, right, up, or down');
    }

    // Use faster drag for swipe (fewer steps, shorter delay)
    await _fastDrag(startPosition, endPosition);
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
    Offset position;

    // Fast path for coordinate-based long press
    if (matcher is CoordinatesMatcher) {
      position = matcher.offset;
    } else {
      final element = widgetFinder.findElement(matcher, configuration);
      if (element == null) {
        throw Exception('Element matching ${matcher.toJson()} not found');
      }

      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Element does not have a RenderBox');
      }

      if (!renderObject.hasSize) {
        throw Exception('RenderBox does not have a size yet');
      }

      // Get the center position of the widget
      final center = renderObject.size.center(Offset.zero);
      position = renderObject.localToGlobal(center);
    }

    await _dispatchLongPressAtPosition(position, duration);
  }

  Future<void> _dispatchLongPressAtPosition(
    Offset globalPosition,
    Duration duration,
  ) async {
    final pointerId = _nextPointerId++;

    // Build the event records
    final records = [
      // Pointer down
      [
        PointerAddedEvent(position: globalPosition),
        PointerDownEvent(pointer: pointerId, position: globalPosition),
      ],
      // Hold for the duration (with small moves to simulate pressure)
      // Add small movements to keep the gesture active
      [
        PointerMoveEvent(
          pointer: pointerId,
          position: globalPosition + const Offset(0.5, 0.5),
          delta: const Offset(0.5, 0.5),
        ),
      ],
      // Pointer up after duration
      [PointerUpEvent(pointer: pointerId, position: globalPosition)],
    ];

    // Dispatch down event
    records[0].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);

    // Small move to keep gesture active
    records[1].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);

    // Hold for the duration (minus the delays already used)
    final holdDuration = duration - (kDelay * 2);
    if (holdDuration > Duration.zero) {
      await Future<void>.delayed(holdDuration);
    }

    // Dispatch up event
    records[2].forEach(GestureBinding.instance.handlePointerEvent);
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(kDelay);
  }

  /// Simulates a double tap on an element that matches the given [matcher].
  ///
  /// Performs two taps with a short interval (200ms) between them at the same position.
  Future<void> doubleTap(
    WidgetMatcher matcher,
    WidgetFinder widgetFinder,
    FlutterCopilotConfiguration configuration,
  ) async {
    Offset position;

    // Get the position once to ensure both taps are at the same location
    if (matcher is CoordinatesMatcher) {
      position = matcher.offset;
    } else {
      final element = widgetFinder.findElement(matcher, configuration);
      if (element == null) {
        throw Exception('Element matching ${matcher.toJson()} not found');
      }

      final renderObject = element.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Element does not have a RenderBox');
      }

      if (!renderObject.hasSize) {
        throw Exception('RenderBox does not have a size yet');
      }

      // Get the center position of the widget
      final center = renderObject.size.center(Offset.zero);
      position = renderObject.localToGlobal(center);
    }

    // First tap
    await _dispatchTapAtPosition(position);

    // Wait for double tap interval (200ms - shorter for better recognition)
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Second tap at the same position
    await _dispatchTapAtPosition(position);
  }

  /// Performs a fast drag (for swipe gestures) with fewer steps and shorter delays.
  Future<void> _fastDrag(Offset from, Offset to) async {
    final pointerId = _nextPointerId++;

    final delta = to - from;
    final distance = delta.distance;
    // Use larger steps for faster drag (swipe)
    final stepCount = (distance / (kMaxDelta * 2)).ceil().clamp(1, 20).toInt();

    final moveRecords = <List<PointerEvent>>[];
    for (var i = 1; i <= stepCount; i++) {
      final t = i / stepCount;
      final position = Offset.lerp(from, to, t)!;
      final previousPosition =
          i == 1 ? from : Offset.lerp(from, to, (i - 1) / stepCount)!;
      final stepDelta = position - previousPosition;

      moveRecords.add([
        PointerMoveEvent(
          pointer: pointerId,
          position: position,
          delta: stepDelta,
        ),
      ]);
    }

    final records = [
      [
        PointerAddedEvent(position: from),
        PointerDownEvent(pointer: pointerId, position: from),
      ],
      ...moveRecords,
      [PointerUpEvent(pointer: pointerId, position: to)],
    ];

    // Use shorter delay for faster drag
    await _handlePointerEventRecordFast(records);
  }

  /// Handles pointer events with shorter delay for fast gestures.
  Future<void> _handlePointerEventRecordFast(
    List<List<PointerEvent>> records,
  ) async {
    const fastDelay = Duration(milliseconds: 5);
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(fastDelay);
    }
  }

  /// Handles a list of pointer event records by dispatching them with proper timing.
  ///
  /// Similar to Flutter's test framework handlePointerEventRecord, but simplified
  /// for live app execution.
  Future<void> _handlePointerEventRecord(
    List<List<PointerEvent>> records,
  ) async {
    for (final record in records) {
      record.forEach(GestureBinding.instance.handlePointerEvent);
      WidgetsBinding.instance.scheduleFrame();
      await Future<void>.delayed(kDelay);
    }
  }
}
