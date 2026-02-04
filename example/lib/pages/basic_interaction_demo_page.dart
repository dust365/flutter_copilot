import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class BasicInteractionDemoPage extends StatefulWidget {
  const BasicInteractionDemoPage({super.key});

  @override
  State<BasicInteractionDemoPage> createState() => _BasicInteractionDemoPageState();
}

class _BasicInteractionDemoPageState extends State<BasicInteractionDemoPage> {
  final _logger = Logger('BasicInteractionDemoPage');
  int _buttonTapCount = 0;
  int _cardTapCount = 0;
  int _iconTapCount = 0;
  int _fabTapCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('基础交互演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '使用 MCP tap 工具点击以下元素进行测试',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // ElevatedButton 测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ElevatedButton',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('点击次数: $_buttonTapCount'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      key: const ValueKey('test_elevated_button'),
                      onPressed: () {
                        setState(() {
                          _buttonTapCount++;
                        });
                        _logger.info('ElevatedButton tapped: $_buttonTapCount');
                      },
                      child: const Text('点击我 (ElevatedButton)'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // TextButton 测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TextButton',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('点击次数: $_buttonTapCount'),
                    const SizedBox(height: 12),
                    TextButton(
                      key: const ValueKey('test_text_button'),
                      onPressed: () {
                        setState(() {
                          _buttonTapCount++;
                        });
                        _logger.info('TextButton tapped: $_buttonTapCount');
                      },
                      child: const Text('点击我 (TextButton)'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // OutlinedButton 测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OutlinedButton',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('点击次数: $_buttonTapCount'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      key: const ValueKey('test_outlined_button'),
                      onPressed: () {
                        setState(() {
                          _buttonTapCount++;
                        });
                        _logger.info('OutlinedButton tapped: $_buttonTapCount');
                      },
                      child: const Text('点击我 (OutlinedButton)'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 可点击卡片测试
            Card(
              child: InkWell(
                key: const ValueKey('test_tappable_card'),
                onTap: () {
                  setState(() {
                    _cardTapCount++;
                  });
                  _logger.info('Tappable card tapped: $_cardTapCount');
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '可点击卡片',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('点击次数: $_cardTapCount'),
                      const SizedBox(height: 8),
                      const Text(
                        '点击整个卡片区域进行测试',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // IconButton 测试
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'IconButton',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('点击次数: $_iconTapCount'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('test_icon_button_favorite'),
                          icon: const Icon(Icons.favorite),
                          color: Colors.red,
                          onPressed: () {
                            setState(() {
                              _iconTapCount++;
                            });
                            _logger.info('IconButton tapped: $_iconTapCount');
                          },
                        ),
                        IconButton(
                          key: const ValueKey('test_icon_button_star'),
                          icon: const Icon(Icons.star),
                          color: Colors.amber,
                          onPressed: () {
                            setState(() {
                              _iconTapCount++;
                            });
                            _logger.info('IconButton tapped: $_iconTapCount');
                          },
                        ),
                        IconButton(
                          key: const ValueKey('test_icon_button_thumb_up'),
                          icon: const Icon(Icons.thumb_up),
                          color: Colors.blue,
                          onPressed: () {
                            setState(() {
                              _iconTapCount++;
                            });
                            _logger.info('IconButton tapped: $_iconTapCount');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 使用说明
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
                      '使用 MCP tap 工具，通过 key 参数点击上述元素。例如：\n'
                      '• key: "test_elevated_button"\n'
                      '• key: "test_text_button"\n'
                      '• key: "test_tappable_card"\n'
                      '• key: "test_icon_button_favorite"',
                      style: TextStyle(color: Colors.blue[900]),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('test_fab'),
        onPressed: () {
          setState(() {
            _fabTapCount++;
          });
          _logger.info('FAB tapped: $_fabTapCount');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('FAB 被点击了 $_fabTapCount 次'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        tooltip: '点击 FAB',
        child: const Icon(Icons.add),
      ),
    );
  }
}
