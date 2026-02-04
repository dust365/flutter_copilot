import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class TextInputDemoPage extends StatefulWidget {
  const TextInputDemoPage({super.key});

  @override
  State<TextInputDemoPage> createState() => _TextInputDemoPageState();
}

class _TextInputDemoPageState extends State<TextInputDemoPage> {
  final _logger = Logger('TextInputDemoPage');
  final TextEditingController _singleLineController = TextEditingController();
  final TextEditingController _multiLineController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _singleLineController.dispose();
    _multiLineController.dispose();
    _passwordController.dispose();
    _numberController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文本输入演示'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '使用 MCP enter_text 工具在以下文本框中输入内容',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // 单行文本输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '单行文本输入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('single_line_text_field'),
                      controller: _singleLineController,
                      decoration: const InputDecoration(
                        labelText: '输入单行文本',
                        hintText: '例如：Hello World',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        _logger.info('Single line text changed: $value');
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前值: ${_singleLineController.text.isEmpty ? "(空)" : _singleLineController.text}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 多行文本输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '多行文本输入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('multi_line_text_field'),
                      controller: _multiLineController,
                      decoration: const InputDecoration(
                        labelText: '输入多行文本',
                        hintText: '可以输入多行内容',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 4,
                      onChanged: (value) {
                        _logger.info('Multi line text changed: $value');
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前值: ${_multiLineController.text.isEmpty ? "(空)" : _multiLineController.text}',
                      style: const TextStyle(color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 密码输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '密码输入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('password_text_field'),
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: '输入密码',
                        hintText: '密码会被隐藏',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      onChanged: (value) {
                        _logger.info('Password text changed: ${value.length} characters');
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _passwordController.text.isEmpty
                          ? '当前值: (空)'
                          : '当前值: ${"*" * _passwordController.text.length}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 数字输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '数字输入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('number_text_field'),
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: '输入数字',
                        hintText: '例如：12345',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        _logger.info('Number text changed: $value');
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前值: ${_numberController.text.isEmpty ? "(空)" : _numberController.text}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 邮箱输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '邮箱输入',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('email_text_field'),
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: '输入邮箱',
                        hintText: '例如：user@example.com',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (value) {
                        _logger.info('Email text changed: $value');
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前值: ${_emailController.text.isEmpty ? "(空)" : _emailController.text}',
                      style: const TextStyle(color: Colors.grey),
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
                      '使用 MCP enter_text 工具，通过 key 参数指定文本框，通过 input 参数输入内容。例如：\n'
                      '• key: "single_line_text_field", input: "Hello World"\n'
                      '• key: "multi_line_text_field", input: "多行文本\\n第二行"\n'
                      '• key: "password_text_field", input: "mypassword"\n'
                      '• key: "number_text_field", input: "12345"\n'
                      '• key: "email_text_field", input: "user@example.com"',
                      style: TextStyle(color: Colors.blue[900]),
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
}
