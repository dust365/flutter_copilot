import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// State for a single tap feedback display (position and optional timestamp).
class TapFeedbackState {
  TapFeedbackState({
    required this.position,
    DateTime? shownAt,
  }) : _shownAt = shownAt ?? DateTime.now();

  final Offset position;
  final DateTime _shownAt;

  DateTime get shownAt => _shownAt;
}

/// Controller for showing a red dot at tap/gesture positions (e.g. MCP tap).
///
/// Call [showAt] when a tap occurs; listeners (e.g. [TapFeedbackOverlay]) will
/// display a dot at that position. The dot is cleared automatically after
/// [duration].
class TapFeedbackController {
  TapFeedbackController({
    this.duration = const Duration(milliseconds: 1200),
  });

  /// How long the feedback dot stays visible before being cleared.
  final Duration duration;

  final ValueNotifier<TapFeedbackState?> _state = ValueNotifier<TapFeedbackState?>(null);

  /// Notifier for the current feedback state. Null when no dot is shown.
  ValueListenable<TapFeedbackState?> get state => _state;

  Timer? _clearTimer;

  /// Shows a feedback dot at [position]. Any previous dot is replaced and the
  /// clear timer is reset.
  void showAt(Offset position) {
    _clearTimer?.cancel();
    _state.value = TapFeedbackState(position: position);
    _clearTimer = Timer(duration, () {
      _clearTimer = null;
      _state.value = null;
    });
  }

  /// Clears the current feedback dot immediately.
  void clear() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _state.value = null;
  }

  /// Disposes the controller. Call when the binding or overlay is disposed.
  void dispose() {
    _clearTimer?.cancel();
    _state.value = null;
  }
}
