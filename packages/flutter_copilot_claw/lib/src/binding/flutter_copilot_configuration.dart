import 'package:flutter/material.dart';

/// Configuration for the Flutter Copilot MCP extensions.
///
/// 用于自定义 MCP 如何识别可交互元素、提取文本和截屏尺寸。标准 Flutter 组件
///（如 [ElevatedButton]、[TextField]、[Switch] 等）已内置支持，无需配置。
///
/// 传入方式：[FlutterCopilotBinding.ensureInitialized] 或
/// [FlutterCopilotBinding.runAppWithConfig] 的第二参数。
///
/// 配置项说明见 README 的「FlutterCopilotConfiguration 配置项」。
class FlutterCopilotConfiguration {
  const FlutterCopilotConfiguration({
    this.isInteractiveWidget,
    this.shouldStopTraversal,
    this.extractText,
    this.maxScreenshotSize = const Size(2000, 2000),
    this.enableGlobalRebuildHook = true,
  });

  /// 将自定义组件类型标记为「可交互」。
  ///
  /// 返回 true 的类型会出现在 [get_interactive_elements] 中，可被 tap、enter_text 等定位。
  /// 仅在未命中内置可交互组件时调用。
  final bool Function(Type type)? isInteractiveWidget;

  /// 遍历组件树时，遇到该类型则不再向下遍历。
  ///
  /// 用于封装型组件（如自定义卡片），避免暴露大量内部子节点。仅在未命中内置停止类型时调用。
  final bool Function(Type type)? shouldStopTraversal;

  /// 从自定义 Widget 实例中提取显示文本。
  ///
  /// 该文本会出现在元素列表的 text 字段中，并用于按 text 匹配。仅在未命中内置文本提取时调用。
  final String? Function(Widget widget)? extractText;

  /// 截屏最大物理像素尺寸（宽×高），超出会按比例缩小；null 表示不限制。
  final Size? maxScreenshotSize;

  /// 是否开启全局重建 Hook（用于组件重绘监测）。
  ///
  /// 为 true 时，[FlutterCopilotBinding] 初始化会调用 [enableGlobalRebuildHook]，
  /// 对 Widget 的 build 进行全局统计，供 snapshot/timeline/diff 等扩展使用。
  /// 默认 true；release 下若需节省开销可显式传 false。
  final bool enableGlobalRebuildHook;

  /// Checks if a widget type is interactive (built-in + custom).
  bool isInteractiveWidgetType(Type type) {
    return _isBuiltInInteractiveWidget(type) || (isInteractiveWidget?.call(type) ?? false);
  }

  /// Returns whether traversal should stop at the given widget type.
  bool shouldStopAtType(Type type) {
    if (_isBuiltInStopWidget(type)) {
      return true;
    } else if (shouldStopTraversal != null) {
      return shouldStopTraversal!(type);
    } else {
      return false;
    }
  }

  /// Extracts text from a widget (built-in + custom).
  String? extractTextFromWidget(Widget widget) {
    final builtInText = _extractBuiltInText(widget);
    return builtInText ?? extractText?.call(widget);
  }

  // Built-in Flutter widget support

  static bool _isBuiltInInteractiveWidget(Type type) {
    return type == Checkbox ||
        type == CheckboxListTile ||
        type == DropdownButton ||
        type == DropdownButtonFormField ||
        type == ElevatedButton ||
        type == FilledButton ||
        type == FloatingActionButton ||
        type == GestureDetector ||
        type == IconButton ||
        type == InkWell ||
        type == OutlinedButton ||
        type == PopupMenuButton ||
        type == Radio ||
        type == RadioListTile ||
        type == Slider ||
        type == Switch ||
        type == SwitchListTile ||
        type == TextButton ||
        type == TextField ||
        type == TextFormField ||
        type == ButtonStyleButton;
  }

  static bool _isBuiltInStopWidget(Type type) {
    return (type != GestureDetector && type != InkWell) &&
        (_isBuiltInInteractiveWidget(type) || type == Text);
  }

  static String? _extractBuiltInText(Widget widget) {
    if (widget is Text) {
      return widget.data ?? widget.textSpan?.toPlainText();
    }
    if (widget is RichText) {
      return widget.text.toPlainText();
    }
    if (widget is EditableText) {
      return widget.controller.text;
    }
    if (widget is TextField) {
      return widget.controller?.text;
    }
    if (widget is TextFormField) {
      return widget.controller?.text;
    }
    return null;
  }
}
