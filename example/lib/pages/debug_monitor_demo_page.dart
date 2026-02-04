import 'package:flutter/material.dart';

class DebugMonitorDemoPage extends StatefulWidget {
  const DebugMonitorDemoPage({super.key});

  @override
  State<DebugMonitorDemoPage> createState() => _DebugMonitorDemoPageState();
}

class _DebugMonitorDemoPageState extends State<DebugMonitorDemoPage> {
  int _infoLogCount = 0;
  int _warningLogCount = 0;
  int _errorLogCount = 0;
  int _debugLogCount = 0;
  final List<String> _logHistory = [];

  @override
  void initState() {
    super.initState();
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console: 调试与监控演示页面已初始化');
  }

  void _logInfo() {
    _infoLogCount++;
    final message = '这是一条信息日志 #$_infoLogCount - ${DateTime.now().toIso8601String()}';
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console output: $message');
    setState(() {
      _logHistory.add('[INFO] $message');
    });
  }

  void _logWarning() {
    _warningLogCount++;
    final message = '这是一条警告日志 #$_warningLogCount - 可能存在潜在问题';
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console warning: $message');
    setState(() {
      _logHistory.add('[WARNING] $message');
    });
  }

  void _logError() {
    _errorLogCount++;
    final message = '这是一条错误日志 #$_errorLogCount - 模拟错误情况';
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console error: $message');
    setState(() {
      _logHistory.add('[ERROR] $message');
    });
  }

  void _logDebug() {
    _debugLogCount++;
    final message = '这是一条调试日志 #$_debugLogCount - 调试信息';
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console debug: $message');
    setState(() {
      _logHistory.add('[DEBUG] $message');
    });
  }

  void _logWithStackTrace() {
    try {
      throw Exception('这是一个模拟异常，用于演示堆栈跟踪');
    } catch (e, stackTrace) {
      // Print to console (will be captured by LogCollector)
      // ignore: avoid_print
      print('Console error: 捕获到异常: $e');
      // ignore: avoid_print
      print('Stack trace: ${stackTrace.toString().split('\n').take(10).join('\n')}');
      setState(() {
        _logHistory.add('[ERROR] 异常: $e');
        _logHistory.add('[STACK] ${stackTrace.toString().split('\n').take(5).join('\n')}');
      });
    }
  }

  void _logUserAction(String action) {
    // Print to console (will be captured by LogCollector)
    // ignore: avoid_print
    print('Console: 用户操作: $action - ${DateTime.now().toIso8601String()}');
    setState(() {
      _logHistory.add('[ACTION] $action');
    });
  }

  void _clearLogHistory() {
    setState(() {
      _logHistory.clear();
      _infoLogCount = 0;
      _warningLogCount = 0;
      _errorLogCount = 0;
      _debugLogCount = 0;
    });
    // ignore: avoid_print
    print('Console: 日志历史已清空');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调试与监控演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 说明卡片
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          '使用 get_logs MCP 工具',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '这个页面演示如何使用 get_logs 工具获取应用日志。'
                      '点击下面的按钮生成不同类型的日志，然后使用 MCP 工具 get_logs 来获取这些日志。',
                      style: TextStyle(color: Colors.blue[800]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '提示：使用 AI 智能体调用 get_logs 工具来查看收集到的日志。',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 日志统计
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '日志统计',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('信息', _infoLogCount, Colors.blue, Icons.info),
                        _buildStatCard('警告', _warningLogCount, Colors.orange, Icons.warning),
                        _buildStatCard('错误', _errorLogCount, Colors.red, Icons.error),
                        _buildStatCard('调试', _debugLogCount, Colors.green, Icons.bug_report),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 生成日志按钮
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '生成日志',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ElevatedButton.icon(
                          key: const ValueKey('log_info_button'),
                          onPressed: () {
                            _logInfo();
                            _logUserAction('点击了"生成信息日志"按钮');
                          },
                          icon: const Icon(Icons.info),
                          label: const Text('信息日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('log_warning_button'),
                          onPressed: () {
                            _logWarning();
                            _logUserAction('点击了"生成警告日志"按钮');
                          },
                          icon: const Icon(Icons.warning),
                          label: const Text('警告日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('log_error_button'),
                          onPressed: () {
                            _logError();
                            _logUserAction('点击了"生成错误日志"按钮');
                          },
                          icon: const Icon(Icons.error),
                          label: const Text('错误日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('log_debug_button'),
                          onPressed: () {
                            _logDebug();
                            _logUserAction('点击了"生成调试日志"按钮');
                          },
                          icon: const Icon(Icons.bug_report),
                          label: const Text('调试日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('log_stacktrace_button'),
                          onPressed: () {
                            _logWithStackTrace();
                            _logUserAction('点击了"生成堆栈跟踪"按钮');
                          },
                          icon: const Icon(Icons.track_changes),
                          label: const Text('堆栈跟踪'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 本地日志历史（仅用于显示，实际日志通过 get_logs 获取）
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '本地日志历史（预览）',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('clear_logs_button'),
                          onPressed: _clearLogHistory,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '注意：这只是本地预览。使用 get_logs MCP 工具可以获取完整的应用日志。',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: _logHistory.isEmpty
                          ? Center(
                              child: Text(
                                '暂无日志\n点击上方按钮生成日志',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _logHistory.length,
                              itemBuilder: (context, index) {
                                final log = _logHistory[index];
                                Color? logColor;
                                if (log.contains('[INFO]')) {
                                  logColor = Colors.blue;
                                } else if (log.contains('[WARNING]')) {
                                  logColor = Colors.orange;
                                } else if (log.contains('[ERROR]')) {
                                  logColor = Colors.red;
                                } else if (log.contains('[DEBUG]')) {
                                  logColor = Colors.green;
                                } else {
                                  logColor = Colors.grey;
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      color: logColor,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 使用说明
            Card(
              color: Colors.amber[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber[700]),
                        const SizedBox(width: 8),
                        Text(
                          '如何使用 get_logs 工具',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep(
                      '1',
                      '点击上方按钮生成不同类型的日志（信息、警告、错误、调试等）',
                    ),
                    _buildInstructionStep(
                      '2',
                      '在 AI 智能体中调用 get_logs 工具来获取应用日志',
                    ),
                    _buildInstructionStep(
                      '3',
                      '分析日志内容，包括日志级别、时间戳、消息和堆栈跟踪',
                    ),
                    _buildInstructionStep(
                      '4',
                      '使用日志来调试问题、监控应用状态或验证功能',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionStep(String step, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.amber[700],
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(color: Colors.amber[900]),
            ),
          ),
        ],
      ),
    );
  }
}
