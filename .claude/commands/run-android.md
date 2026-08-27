# Run Android

在 Android 真机或模拟器上运行 Flutter 项目。

## 执行步骤

1. **列出当前已连接的 Android 设备**
   - 执行：`adb devices`
   - 解析输出中状态为 `device` 的行（过滤掉 `unauthorized` / `offline` 等状态）
   - 如果没有任何状态为 `device` 的记录：
     - 提示：未检测到可用的 Android 设备，请确认：
       1）真机已开启开发者模式和 USB 调试
       2）数据线已正确连接
       3）若是模拟器，确保已启动
     - 然后终止命令

2. **从 adb 输出中选择一个设备 ID**
   - 一般取第一条 `device` 状态的设备 ID
   - 例如：`R3CN30XXXXX	device` → 设备 ID 为：`R3CN30XXXXX`

3. **验证 Flutter 能识别该 Android 设备**
   - 执行：`flutter devices`
   - 检查输出中是否包含上一步选择的设备 ID，且平台为 android
   - 如果 Flutter 无法识别该设备：
     - 提示：Flutter 未识别到该 Android 设备，请检查 Android Studio / SDK 配置
     - 然后终止命令

4. **在选定的 Android 设备上运行 Flutter 项目**
   - 使用上面获取到的设备 ID，通过 `flutter_run.sh` 启动（脚本会自动捕获 VM Service URI 并写入 `.vm_service_uri`）：
     - `./scripts/flutter_run.sh -d <deviceId>`
   - 只运行 Android，不加其它设备参数
   - 如项目需要特定 flavor 或 dart-define，可按需扩展

5. **获取 VM Service URI 并连接 Flutter Copilot**
   - 等待 `.vm_service_uri` 文件出现（脚本检测到 URI 后自动写入）：
     - `while [ ! -f .vm_service_uri ]; do sleep 1; done && cat .vm_service_uri`
   - 读取文件内容即为 `ws://127.0.0.1:PORT/TOKEN/ws` 格式的 URI
   - 使用该 URI 调用 Flutter Copilot 的 `connect` 工具建立连接