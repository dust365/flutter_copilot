import 'package:flutter/scheduler.dart';

/// Tracks widget rebuild counts for repaint monitoring (snapshot / timeline / diff).
///
/// Initialized by [FlutterCopilotBinding.enableGlobalRebuildHook] when
/// [FlutterCopilotConfiguration.enableGlobalRebuildHook] is true.
/// [CopilotBuildOwner.scheduleBuildFor] calls [recordBuild] for each scheduled element.
class WidgetRebuildTracker {
  WidgetRebuildTracker._() {
    _scheduleFrameEnd();
  }

  static WidgetRebuildTracker? _instance;

  /// Singleton. Null until [ensureInitialized] is called (typically from binding).
  static WidgetRebuildTracker? get instance => _instance;

  /// Creates the tracker and starts frame-based aggregation. Idempotent.
  static WidgetRebuildTracker ensureInitialized() {
    if (_instance == null) {
      _instance = WidgetRebuildTracker._();
    }
    return _instance!;
  }

  int _frame = 0;
  final Map<String, int> _globalCounts = {};
  final Map<String, int> _currentFrameCounts = {};

  void _scheduleFrameEnd() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _onFrameEnd();
    });
  }

  void _onFrameEnd() {
    for (final e in _currentFrameCounts.entries) {
      _globalCounts[e.key] = (_globalCounts[e.key] ?? 0) + e.value;
    }
    _currentFrameCounts.clear();
    _frame++;
    _scheduleFrameEnd();
  }

  /// Records one build for the given widget type and optional key.
  void recordBuild(String widgetType, String? key) {
    final k = key == null || key.isEmpty ? widgetType : '$widgetType#$key';
    _currentFrameCounts[k] = (_currentFrameCounts[k] ?? 0) + 1;
  }

  /// Returns current snapshot: frame, total rebuilds, and top widgets.
  Map<String, dynamic> getSnapshot({int topLimit = 20}) {
    final total = _globalCounts.values.fold<int>(0, (a, b) => a + b);
    final entries = _globalCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(topLimit).map((e) {
      final parts = e.key.split('#');
      final type = parts[0];
      final key = parts.length > 1 ? parts.sublist(1).join('#') : null;
      final count = e.value;
      final percent = total > 0 ? (count / total * 100) : 0.0;
      return <String, dynamic>{
        'type': type,
        'key': key,
        'count': count,
        'percent': percent.toStringAsFixed(1),
      };
    }).toList();

    return <String, dynamic>{
      'frame': _frame,
      'total': total,
      'top': top,
    };
  }

  /// Clears all counts and resets frame. Optional for demo / testing.
  void clear() {
    _globalCounts.clear();
    _currentFrameCounts.clear();
    _frame = 0;
  }
}
