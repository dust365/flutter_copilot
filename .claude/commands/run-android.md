# Run Android

1. 使用 `fcc --project example --json devices` 列出设备，保留 Android 候选。其他项目传实际 Flutter 工程目录。
2. 一台可用 Android 设备时直接使用；多台时让用户选择一台或多台。
3. 执行 `fcc --project example up -d <device-id>`，多选时重复传 `-d`。MCP 同样可调用 `ensure_apps` 并传 `deviceIds`，用 `operation_status` 查看启动结果。
4. 使用返回的 App ID 截图或检查元素。已经由 `flutter run` 启动时，先用 `fcc apps` 或 `list_apps` 复用。
