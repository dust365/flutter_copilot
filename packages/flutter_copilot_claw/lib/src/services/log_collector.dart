import 'dart:collection';

// Temporarily disabled: logging package import
// Uncomment if you want to capture logging package logs:
// import 'package:logging/logging.dart';

/// Collects and stores Flutter logs for retrieval via VM service extension.
class LogCollector {
  final _logs = Queue<String>();
  static const _maxLogs = 1000;
  bool _initialized = false;
  static LogCollector? _instance;

  /// Gets the singleton instance of LogCollector.
  static LogCollector? get instance => _instance;

  /// Initializes the log collector to start capturing logs.
  void initialize() {
    if (_initialized) {
      return;
    }

    _instance = this;

    // Temporarily disabled: Capture logging package logs
    // Uncomment the following code if you want to capture logging package logs:
    // Logger.root.onRecord.listen((record) {
    //   _addLog(_formatLogRecord(record));
    // });

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

  // Temporarily disabled: Format logging package log records
  // Uncomment this method if you want to capture logging package logs:
  // String _formatLogRecord(LogRecord record) {
  //   final buffer = StringBuffer()
  //     ..write('[')
  //     ..write(_formatTime(record.time))
  //     ..write('][')
  //     ..write(record.level.name.toUpperCase())
  //     ..write('][')
  //     ..write(record.loggerName)
  //     ..write('] ')
  //     ..write(record.message);
  //
  //   if (record.error != null) {
  //     buffer.write('\n  Error: ${record.error}');
  //   }
  //
  //   if (record.stackTrace != null) {
  //     buffer.write('\n  Stack trace:\n');
  //     final stackLines = record.stackTrace.toString().split('\n');
  //     for (final line in stackLines) {
  //       if (line.isNotEmpty) {
  //         buffer.write('    $line\n');
  //       }
  //     }
  //   }
  //
  //   return buffer.toString();
  // }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
  }
}
