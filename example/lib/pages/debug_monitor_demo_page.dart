import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

class DebugMonitorDemoPage extends StatefulWidget {
  const DebugMonitorDemoPage({super.key});

  @override
  State<DebugMonitorDemoPage> createState() => _DebugMonitorDemoPageState();
}

class _DebugMonitorDemoPageState extends State<DebugMonitorDemoPage> {
  int _count = 0;
  final List<_LogEntry> _sent = [];

  void _addLog({required bool isError}) {
    _count++;
    final ts = DateTime.now().toIso8601String();
    final message = '${isError ? 'Error' : 'Info'} log #$_count at $ts';
    FlutterCopilotBinding.addLog(message, isError: isError);
    setState(() {
      _sent.insert(0, _LogEntry(message: message, isError: isError));
    });
  }

  void _clear() {
    setState(() {
      _sent.clear();
      _count = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 16),
            _buildActionRow(),
            const SizedBox(height: 16),
            Expanded(child: _buildSentList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Card(
      color: Colors.indigo.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text(
                  'MCP get_logs 演示',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '1. 点击按钮 → 调用 FlutterCopilotBinding.addLog()\n'
              '2. 在 AI 中调用 MCP 工具 get_logs\n'
              '3. 应可读取到下方列表中的条目',
              style: TextStyle(color: Colors.indigo.shade800, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            key: const ValueKey('log_copilot_info_button'),
            onPressed: () => _addLog(isError: false),
            icon: const Icon(Icons.add_comment),
            label: const Text('写入 Info 日志'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            key: const ValueKey('log_copilot_error_button'),
            onPressed: () => _addLog(isError: true),
            icon: const Icon(Icons.error_outline),
            label: const Text('写入 Error 日志'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSentList() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                const Icon(Icons.list_alt, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '已写入 $_count 条 · 调用 get_logs 可读取',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('clear_logs_button'),
                  onPressed: _sent.isEmpty ? null : _clear,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('清空'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _sent.isEmpty
                ? Center(
                    child: Text(
                      '尚未写入日志\n点击上方按钮开始',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _sent.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _sent[i];
                      final color = e.isError ? Colors.deepOrange : Colors.teal;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          e.isError ? Icons.error : Icons.info,
                          color: color,
                        ),
                        title: Text(
                          e.message,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          e.isError ? 'isError: true' : 'isError: false',
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  _LogEntry({required this.message, required this.isError});
  final String message;
  final bool isError;
}
