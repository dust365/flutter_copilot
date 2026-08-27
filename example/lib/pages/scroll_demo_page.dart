import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class ScrollDemoPage extends StatefulWidget {
  const ScrollDemoPage({super.key});

  @override
  State<ScrollDemoPage> createState() => _ScrollDemoPageState();
}

class _ScrollDemoPageState extends State<ScrollDemoPage> {
  final _logger = Logger('ScrollDemoPage');

  @override
  Widget build(BuildContext context) {
    // 演示只使用单层嵌套：
    // - 外层一个垂直可滚动（CustomScrollView）——scroll_to 的默认目标
    // - 内部一个水平 ListView（不同轴，只算一层嵌套）
    return Scaffold(
      appBar: AppBar(
        title: const Text('滚动演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: CustomScrollView(
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '使用 MCP scroll_to 工具滚动到指定元素',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '垂直列表（页面主滚动）',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: 50,
              itemBuilder: (context, index) {
                return Card(
                  key: ValueKey('vertical_item_$index'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text('列表项 ${index + 1}'),
                    subtitle: Text('这是第 ${index + 1} 个列表项，用于测试滚动功能'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _logger.info('Vertical list item $index tapped');
                    },
                  ),
                );
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    '水平滚动列表',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: 20,
                      itemBuilder: (context, index) {
                        return Container(
                          key: ValueKey('horizontal_item_$index'),
                          width: 150,
                          margin: const EdgeInsets.only(right: 8),
                          child: Card(
                            color: Colors.primaries[
                                index % Colors.primaries.length],
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '项 ${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Icon(Icons.star, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    key: const ValueKey('bottom_target'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.flag, size: 48, color: Colors.blue),
                        SizedBox(height: 8),
                        Text(
                          '页面底部目标元素',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '滚动到这里测试 scroll_to 功能',
                          style: TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Text(
                                '使用说明',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '使用 MCP scroll_to 工具，通过 key 参数指定要滚动到的元素。例如：\n'
                            '• key: "vertical_item_25" - 滚动到垂直列表的第 25 项\n'
                            '• key: "bottom_target" - 滚动到页面底部目标元素\n\n'
                            '注：页面仅保留单层嵌套（外层垂直 + 内部水平），避免多 Scrollable 冲突。水平方向的精确定位建议通过 swipe 工具配合完成。',
                            style: TextStyle(color: Colors.blue[900]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
