import 'package:flutter/material.dart';

/// Information about a demo page
class DemoPageInfo {
  final String title;
  final String description;
  final String route;
  final IconData icon;
  final Color? color;

  const DemoPageInfo({
    required this.title,
    required this.description,
    required this.route,
    required this.icon,
    this.color,
  });
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  // 定义测试页面列表
  static final List<DemoPageInfo> demoPages = [
    const DemoPageInfo(
      title: '基础交互',
      description: '测试 tap 工具 - 点击各种按钮和交互元素',
      route: '/basic-interaction-demo',
      icon: Icons.touch_app,
      color: Colors.blue,
    ),
    const DemoPageInfo(
      title: '文本输入',
      description: '测试 enter_text 工具 - 在文本框中输入内容',
      route: '/text-input-demo',
      icon: Icons.text_fields,
      color: Colors.green,
    ),
    const DemoPageInfo(
      title: '滚动',
      description: '测试 scroll_to 工具 - 滚动到指定元素',
      route: '/scroll-demo',
      icon: Icons.swap_vert,
      color: Colors.orange,
    ),
    const DemoPageInfo(
      title: '手势',
      description: '测试拖拽、滑动、双击、长按等手势操作',
      route: '/gesture-demo',
      icon: Icons.gesture,
      color: Colors.purple,
    ),
    const DemoPageInfo(
      title: '导航',
      description: '测试 navigate 工具 - 页面导航控制',
      route: '/navigation-demo',
      icon: Icons.navigation,
      color: Colors.teal,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Copilot 功能演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: demoPages.length,
        itemBuilder: (context, index) {
          final pageInfo = demoPages[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 16.0),
            elevation: 2,
            child: InkWell(
              onTap: () {
                Navigator.pushNamed(context, pageInfo.route);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: (pageInfo.color ?? Colors.grey).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        pageInfo.icon,
                        color: pageInfo.color ?? Colors.grey,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pageInfo.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pageInfo.description,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
