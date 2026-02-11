import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_copilot_claw/flutter_copilot_claw.dart';

/// 用于演示「单组件不断重绘」的错误示例。
/// 自身 Timer 每 100ms 触发 setState，会在 get_rebuild_snapshot 中单独冲高，
/// 便于测试 MCP 能否定位到具体问题组件。
class ConstantlyRebuildingTile extends StatefulWidget {
  const ConstantlyRebuildingTile({
    Key? key,
    required this.running,
  }) : super(key: key ?? const ValueKey<String>('demo_single_bad_rebuild'));

  final bool running;

  @override
  State<ConstantlyRebuildingTile> createState() => _ConstantlyRebuildingTileState();
}

class _ConstantlyRebuildingTileState extends State<ConstantlyRebuildingTile> {
  Timer? _timer;
  int _tick = 0;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.running) _startTimer();
  }

  @override
  void didUpdateWidget(ConstantlyRebuildingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.running && !oldWidget.running) {
      _startTimer();
    } else if (!widget.running && oldWidget.running) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: widget.running ? 4 : 1,
      color: widget.running ? Colors.red[50] : Colors.grey[200],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              widget.running ? Icons.warning_amber_rounded : Icons.widgets_outlined,
              size: 32,
              color: widget.running ? Colors.red[700] : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.running ? '此组件在不停重绘（错误示例）' : '单组件错误重绘示例',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: widget.running ? Colors.red[900] : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.running
                        ? 'ConstantlyRebuildingTile 每 100ms setState，用 MCP get_rebuild_snapshot 可定位到本组件'
                        : '点击下方按钮开启后，仅本组件会反复重建，便于验证 MCP 定位能力',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                  if (widget.running) ...[
                    const SizedBox(height: 6),
                    Text(
                      'tick: $_tick',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.red[800],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 重绘监测演示：通过**实时重建计数**和**定时器模拟**，
/// 直观感受「错误重绘」时数字飞涨、问题区高亮，再用 snapshot 看热点。
class RebuildDemoPage extends StatefulWidget {
  const RebuildDemoPage({super.key});

  @override
  State<RebuildDemoPage> createState() => _RebuildDemoPageState();
}

class _RebuildDemoPageState extends State<RebuildDemoPage> {
  Timer? _badRepaintTimer;
  Timer? _statsRefreshTimer;
  static const Duration _timerInterval = Duration(milliseconds: 80);
  static const Duration _statsRefreshInterval = Duration(milliseconds: 300);

  /// 定时器触发次数 = 整页被强制 setState 的次数，开启后飞涨
  int _timerTriggerCount = 0;

  /// 单组件错误重绘示例：仅 ConstantlyRebuildingTile 在反复 setState
  bool _singleWidgetBadRebuildRunning = false;

  /// 从 Tracker 拉取的全局总重建次数，定时刷新
  int _globalTotalRebuilds = 0;
  Map<String, dynamic>? _snapshot;
  String? _snapshotError;

  @override
  void dispose() {
    _badRepaintTimer?.cancel();
    _statsRefreshTimer?.cancel();
    super.dispose();
  }

  void _startBadRepaint() {
    _badRepaintTimer?.cancel();
    _statsRefreshTimer?.cancel();
    _timerTriggerCount = 0;
    _statsRefreshTimer = Timer.periodic(_statsRefreshInterval, (_) {
      if (!mounted) return;
      final t = WidgetRebuildTracker.instance;
      if (t != null) {
        final snap = t.getSnapshot(topLimit: 5);
        setState(() {
          _globalTotalRebuilds = snap['total'] as int? ?? 0;
        });
      }
    });
    _badRepaintTimer = Timer.periodic(_timerInterval, (_) {
      if (!mounted) return;
      setState(() => _timerTriggerCount++);
    });
    setState(() {});
  }

  void _stopBadRepaint() {
    _badRepaintTimer?.cancel();
    _statsRefreshTimer?.cancel();
    _badRepaintTimer = null;
    _statsRefreshTimer = null;
    setState(() {});
  }

  void _refreshSnapshot() {
    final tracker = WidgetRebuildTracker.instance;
    if (tracker == null) {
      setState(() {
        _snapshot = null;
        _snapshotError = '未开启重建监测 (enableGlobalRebuildHook = false 或当前为 Web)';
      });
      return;
    }
    try {
      final snapshot = tracker.getSnapshot(topLimit: 12);
      setState(() {
        _snapshot = snapshot;
        _snapshotError = null;
        _globalTotalRebuilds = snapshot['total'] as int? ?? 0;
      });
    } catch (e) {
      setState(() {
        _snapshot = null;
        _snapshotError = e.toString();
      });
    }
  }

  void _clearSnapshot() {
    WidgetRebuildTracker.instance?.clear();
    setState(() {
      _snapshot = null;
      _snapshotError = null;
      _globalTotalRebuilds = 0;
      _timerTriggerCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = _badRepaintTimer != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('重绘监测'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLiveCountCard(running),
            const SizedBox(height: 20),
            _buildProblemZoneCard(running),
            const SizedBox(height: 20),
            _buildControlCard(running),
            const SizedBox(height: 20),
            _buildSingleWidgetBadRebuildCard(),
            const SizedBox(height: 20),
            _buildSnapshotCard(),
            const SizedBox(height: 20),
            _buildHintCard(),
          ],
        ),
      ),
    );
  }

  /// 顶部大数字：本页 build 次数 + 全局重建次数，定时器一开就飞涨，直观感受问题
  Widget _buildLiveCountCard(bool running) {
    return Card(
      elevation: running ? 4 : 1,
      color: running ? Colors.red[50] : Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.warning_amber_rounded : Icons.analytics_outlined,
                  size: 28,
                  color: running ? Colors.red[700] : Colors.grey[700],
                ),
                const SizedBox(width: 10),
                Text(
                  running ? '正在发生大量重绘' : '当前重绘统计',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: running ? Colors.red[900] : Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBigNumber('定时器触发次数', _timerTriggerCount, running),
                _buildBigNumber('全局调度重建', _globalTotalRebuilds, running),
              ],
            ),
            if (running) ...[
              const SizedBox(height: 12),
              Text(
                '数字快速增加 = 整页被反复 setState 重建，子树大量 scheduleBuildFor，属于典型性能问题',
                style: TextStyle(fontSize: 13, color: Colors.red[800]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBigNumber(String label, int value, bool running) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: running ? Colors.red[700] : Colors.deepPurple[700],
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// 问题区：定时器开启时高亮，让人一眼看到「这块在出问题」
  Widget _buildProblemZoneCard(bool running) {
    return Card(
      elevation: running ? 4 : 1,
      color: running ? Colors.orange[100] : null,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              running ? Icons.error_outline : Icons.check_circle_outline,
              size: 40,
              color: running ? Colors.orange[800] : Colors.green[700],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    running ? '问题区：整页被定时器反复 setState，所有子组件都在重建' : '正常：无定时器触发，仅用户操作时重建',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: running ? Colors.orange[900] : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    running ? '这就是「错误重绘」—— 没有数据变化却整页 rebuild，浪费 CPU、可能卡顿' : '点击下方「开始错误重绘」可模拟问题',
                    style: TextStyle(
                      fontSize: 13,
                      color: running ? Colors.orange[800] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(bool running) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '模拟控制',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: running ? null : _startBadRepaint,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('开始错误重绘'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: running ? _stopBadRepaint : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '定时器每 ${_timerInterval.inMilliseconds}ms 触发 setState，整页 rebuild；开启后注意上方数字飞涨',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  /// 单组件错误重绘示例：仅 [ConstantlyRebuildingTile] 在反复 setState，
  /// 用于测试 MCP get_rebuild_snapshot 能否定位到具体问题组件。
  Widget _buildSingleWidgetBadRebuildCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bug_report_outlined, color: Colors.teal[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  '单组件错误重绘（测试 MCP 定位）',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstantlyRebuildingTile(running: _singleWidgetBadRebuildRunning),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _singleWidgetBadRebuildRunning
                      ? null
                      : () => setState(() => _singleWidgetBadRebuildRunning = true),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('开始单组件错误重绘'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _singleWidgetBadRebuildRunning
                      ? () => setState(() => _singleWidgetBadRebuildRunning = false)
                      : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('停止'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '仅上方一块区域内的组件会每 100ms 重建。用 MCP get_rebuild_snapshot 可看到 ConstantlyRebuildingTile 或 demo_single_bad_rebuild 排在前面，从而定位到问题组件。',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '重建快照（Top 组件）',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Wrap(
                  spacing: 0,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _refreshSnapshot,
                      icon: const Icon(Icons.refresh, size: 20),
                      label: const Text('刷新'),
                    ),
                    TextButton.icon(
                      onPressed: _clearSnapshot,
                      icon: const Icon(Icons.clear_all, size: 20),
                      label: const Text('清空'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_snapshotError != null)
              Text(_snapshotError!, style: TextStyle(color: Colors.red[700], fontSize: 13))
            else if (_snapshot == null)
              Text(
                '点击「刷新」或先「开始错误重绘」再刷新，查看哪些组件重建最多',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              )
            else
              _buildSnapshotContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildSnapshotContent() {
    final frame = _snapshot!['frame'] as int? ?? 0;
    final total = _snapshot!['total'] as int? ?? 0;
    final top = _snapshot!['top'] as List<dynamic>? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildStatChip('帧', '$frame'),
            const SizedBox(width: 8),
            _buildStatChip('总重建', '$total'),
          ],
        ),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...top.map<Widget>((e) {
            final map = e as Map<String, dynamic>;
            final type = map['type'] as String? ?? '?';
            final key = map['key'] as String?;
            final count = map['count'] as int? ?? 0;
            final percent = map['percent'] as String? ?? '0';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                key != null && key.isNotEmpty
                    ? '$type ($key): $count ($percent%)'
                    : '$type: $count ($percent%)',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child:
          Text('$label: $value', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
    );
  }

  Widget _buildHintCard() {
    return Card(
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber[700], size: 22),
                const SizedBox(width: 8),
                Text(
                  '如何直观感受',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber[900]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '1. 点击「开始错误重绘」→ 整页被定时器 setState，问题区变橙红色；用 get_rebuild_snapshot 看 RebuildDemoPage 排第一。\n'
              '2. 点击「开始单组件错误重绘」→ 仅一块区域内的组件在重建；用 get_rebuild_snapshot 可定位到 ConstantlyRebuildingTile#demo_single_bad_rebuild。\n'
              '3. 点击「刷新」或 MCP get_rebuild_snapshot 看重绘热点排行，找出问题组件。',
              style: TextStyle(fontSize: 13, color: Colors.amber[900], height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
