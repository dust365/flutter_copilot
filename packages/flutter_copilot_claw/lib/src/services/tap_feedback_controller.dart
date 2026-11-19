import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Which gesture the on-screen mark represents.
enum TapFeedbackKind {
  /// One ring at the hit point.
  tap,

  /// Two concentric rings at the hit point.
  doubleTap,

  /// Two concentric rings while the press is held.
  longPress,

  /// A straight arrow from the first path point to the last.
  drag,
}

/// Visual mark for the latest copilot gesture.
///
/// A tap carries [position]. A drag or swipe carries the global polyline in
/// [path].
class TapFeedbackState {
  TapFeedbackState({
    required this.position,
    this.kind = TapFeedbackKind.tap,
    List<Offset> path = const <Offset>[],
    DateTime? shownAt,
  })  : path = List<Offset>.unmodifiable(path),
        shownAt = shownAt ?? DateTime.now();

  /// Gesture this mark was drawn for.
  final TapFeedbackKind kind;

  /// Hit point of a tap, or the start of a drag.
  final Offset position;

  /// Global polyline of a drag or swipe, including the start point.
  ///
  /// Empty for taps, long presses, and double taps.
  final List<Offset> path;

  /// When this mark was published. Republishing restarts the visible window.
  final DateTime shownAt;

  /// Whether [path] is long enough to draw as a stroke.
  bool get isDrag => path.length >= 2 && (path.last - path.first).distance >= 1;
}

/// Controller for the on-screen gesture mark (tap point and drag trail).
///
/// Listeners such as [TapFeedbackOverlay] paint [state]. The mark replaces any
/// previous one and is cleared after [duration]. Showing again restarts that
/// window, so the mark stays up for a full [duration] after the gesture ends.
/// The default window is 1.2 seconds. A route change clears it immediately.
class TapFeedbackController {
  TapFeedbackController({
    this.duration = const Duration(milliseconds: 1200),
  });

  /// How long the mark stays visible after it was last shown.
  final Duration duration;

  final ValueNotifier<TapFeedbackState?> _state =
      ValueNotifier<TapFeedbackState?>(null);

  /// Current mark. Null when nothing is shown.
  ValueListenable<TapFeedbackState?> get state => _state;

  Timer? _clearTimer;

  /// Shows a point mark at [position].
  void showAt(Offset position) => showTap(position: position);

  /// Shows a tap, long-press, or double-tap mark at [position].
  void showTap({
    required Offset position,
    TapFeedbackKind kind = TapFeedbackKind.tap,
  }) {
    _publish(TapFeedbackState(position: position, kind: kind));
  }

  /// Shows a drag or swipe trail. [path] is in global coordinates.
  ///
  /// An empty path is ignored. A path that does not move is drawn as a point.
  void showDrag(List<Offset> path) {
    if (path.isEmpty) {
      return;
    }
    _publish(
      TapFeedbackState(
        position: path.first,
        path: path,
        kind: TapFeedbackKind.drag,
      ),
    );
  }

  /// Clears the current mark immediately.
  void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _state.value = null;
  }

  /// Disposes the controller. Call when the binding or overlay is disposed.
  void dispose() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _state.value = null;
  }

  void _publish(TapFeedbackState state) {
    _clearTimer?.cancel();
    _state.value = state;
    _clearTimer = Timer(duration, () {
      _clearTimer = null;
      _state.value = null;
    });
  }
}
