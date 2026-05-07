import 'dart:collection';

/// Collects and stores Flutter logs for retrieval via VM service extension.
/// Logs are collected via [FlutterCopilotBinding.captureLogs] (print +
/// uncaught errors) and custom entries via
/// [LogCollector.addConsoleLogStatic] / [FlutterCopilotBinding.addLog].
class LogCollector {
  final _logs = Queue<String>();
  static const _maxLogs = 1000;
  bool _initialized = false;
  static LogCollector? _instance;

  /// Gets the singleton instance of LogCollector.
  static LogCollector? get instance => _instance;

  /// Initializes the log collector. No logging package is used; collection
  /// is done by Zone in [FlutterCopilotBinding.captureLogs] and custom logs
  /// via [addConsoleLog] / [addConsoleLogStatic].
  void initialize() {
    if (_initialized) {
      return;
    }
    _instance = this;
    _initialized = true;
  }

  /// Adds a log entry, keeping only the most recent logs.
  void _addLog(String log) {
    _logs.add(log);

    // Keep only the most recent logs
    if (_logs.length > _maxLogs) {
      _logs.removeFirst();
    }
  }

  /// Adds a console output log (from print, stdout, or stderr).
  void addConsoleLog(String message, {bool isError = false}) {
    if (!_initialized) return;
    final timestamp = _formatTime(DateTime.now());
    final prefix = isError ? '[CONSOLE_ERROR]' : '[CONSOLE]';
    _addLog('[$timestamp]$prefix $message');
  }

  /// Static method to add console log (for use in Zone print interceptor).
  static void addConsoleLogStatic(String message, {bool isError = false}) {
    _instance?.addConsoleLog(message, isError: isError);
  }

  /// Returns all collected logs as a list of formatted strings.
  List<String> getFormattedLogs() {
    return _logs.toList();
  }

  /// Returns all collected logs as a single formatted text string.
  String getFormattedLogsAsText() {
    return _logs.join('\n');
  }

  /// Clears all collected logs.
  void clear() {
    _logs.clear();
  }

  /// Returns the number of collected logs.
  int get count => _logs.length;

  /// Disposes the log collector and cleans up resources.
  void dispose() {
    _initialized = false;
    _instance = null;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
