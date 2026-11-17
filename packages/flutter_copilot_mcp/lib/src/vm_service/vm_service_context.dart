import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' as logging;
import 'package:flutter_copilot_mcp/src/dtd/dtd_registry.dart';
import 'package:flutter_copilot_mcp/src/process/flutter_run_manager.dart';
import 'package:flutter_copilot_mcp/src/process/machine_output.dart';
import 'package:flutter_copilot_mcp/src/session/app_directory.dart';
import 'package:flutter_copilot_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Passed to every app-scoped tool. Optional while a single app is connected.
const appParameterDescription =
    'App id, device id, or VM service URI. Optional when only one app is connected. Required when several apps are connected.';

/// Context for managing VM service connections and registering MCP tools.
final class VmServiceContext {
  VmServiceContext({
    AppDirectory? apps,
    DtdRegistry? dtds,
    FlutterRunManager? runs,
  })  : apps = apps ?? AppDirectory(),
        _logger = logging.Logger('VmServiceContext') {
    this.dtds = dtds ?? DtdRegistry(this.apps);
    this.runs = runs ?? FlutterRunManager(apps: this.apps, dtds: this.dtds);
    this.apps.listDtds = this.dtds.list;
  }

  final AppDirectory apps;
  late final DtdRegistry dtds;
  late final FlutterRunManager runs;
  final logging.Logger _logger;

  /// Stops owned `flutter run` processes and closes DDS and DTD connections.
  Future<void> close() async {
    await runs.close();
    await dtds.close();
    await apps.close();
  }

  Future<VmServiceConnector> _connector(Map<String, dynamic> args) async {
    final session = await apps.open(args['app'] as String?);
    return session.connector;
  }

  /// Registers all VM service related tools with the MCP server.
  void registerTools(McpServer server) {
    // Connection management tools
    server
      ..registerTool(
        'connect',
        description:
            'Connects to one Flutter app by its DDS WebSocket URI and adds it to the session table. Existing sessions stay connected. Prefer list_dtds and connect_dtd when a Dart Tooling Daemon is available. An http:// VM service address is accepted and converted to ws://.../ws.',
        annotations: const ToolAnnotations(title: 'Connect to App'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'DDS WebSocket URI (ws://127.0.0.1:PORT/TOKEN=/ws), or the http:// address printed by flutter run.',
            ),
            'name': JsonSchema.string(
              description:
                  'Stable name for this app. Later tools pass it as app. Defaults to the URI.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          final uri = args['uri'] as String;
          final name = args['name'] as String?;
          _logger.info('Connecting to app at $uri');

          try {
            final session = await apps.connectUri(uri: uri, id: name);
            return CallToolResult(
              content: [
                TextContent(text: 'Connected ${session.describe()}'),
              ],
            );
          } catch (err) {
            _logger.severe('Failed to connect to app', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to connect to app: $err')],
            );
          }
        },
      )
      ..registerTool(
        'disconnect',
        description:
            'Drops one DDS session. Does not stop a flutter run process started by launch_app; use stop_app for that. With several apps, pass app.',
        annotations: const ToolAnnotations(title: 'Disconnect from App'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Disconnecting from app');

          try {
            final message = await apps.disconnectApp(args['app'] as String?);
            return CallToolResult(content: [TextContent(text: message)]);
          } catch (err) {
            _logger.severe('Error during disconnect', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Error during disconnect: $err')],
            );
          }
        },
      )
      ..registerTool(
        'list_dtds',
        description:
            'Lists Dart Tooling Daemon instances on this machine by running `dart tooling-daemon --list`. Use a local ws:// URI from the result with connect_dtd. This does not connect to anything.',
        annotations: const ToolAnnotations(
          title: 'List DTDs',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          try {
            final listing = await dtds.list();
            return CallToolResult(content: [TextContent(text: listing)]);
          } catch (err) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to list DTDs: $err')],
            );
          }
        },
      )
      ..registerTool(
        'connect_dtd',
        description:
            'Connects to one local Dart Tooling Daemon and adds every registered app that has Flutter Copilot initialized. Later VmServiceRegistered events on this DTD connect automatically, and a restarted app keeps the same name. Passing a VM service URI is rejected.',
        annotations: const ToolAnnotations(title: 'Connect DTD'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'Local DTD URI from list_dtds, ws://127.0.0.1:PORT/TOKEN.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          try {
            final summary = await dtds.connect(args['uri'] as String);
            return CallToolResult(content: [TextContent(text: summary)]);
          } catch (err) {
            _logger.warning('Failed to connect DTD', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to connect DTD: $err')],
            );
          }
        },
      )
      ..registerTool(
        'disconnect_dtd',
        description:
            'Disconnects from a DTD and removes the sessions discovered through it. flutter run processes started by this server keep running until stop_app.',
        annotations: const ToolAnnotations(title: 'Disconnect DTD'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description: 'DTD URI previously passed to connect_dtd.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          try {
            final summary = await dtds.disconnect(args['uri'] as String);
            return CallToolResult(content: [TextContent(text: summary)]);
          } catch (err) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to disconnect DTD: $err')],
            );
          }
        },
      )
      ..registerTool(
        'list_apps',
        description:
            'Lists DDS sessions in this server. Pass an id from this list as app when more than one app is connected.',
        annotations: const ToolAnnotations(
          title: 'List Apps',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          return CallToolResult(content: [TextContent(text: apps.describeAll)]);
        },
      )
      ..registerTool(
        'list_devices',
        description:
            'Lists devices reported by `flutter devices --machine`. Use an id with launch_app.',
        annotations: const ToolAnnotations(
          title: 'List Devices',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          try {
            final devices = await runs.listDevices();
            return CallToolResult(
              content: [TextContent(text: formatFlutterDevices(devices))],
            );
          } catch (err) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to list devices: $err')],
            );
          }
        },
      )
      ..registerTool(
        'launch_app',
        description:
            'Starts `flutter run --print-dtd --machine` for one device, connects its DDS, and subscribes to its DTD. Returns when the app is in the session table. Defaults to debug. The flutter run process exits when this MCP server exits. stop_app does not close the app on the device. Same-target launches (two Android, two iOS, or two of the same desktop OS) wait until the previous one has connected. Other targets run at the same time. Timeout starts when this device\'s turn starts.',
        annotations: const ToolAnnotations(title: 'Launch App'),
        inputSchema: ToolInputSchema(
          properties: {
            'directory': JsonSchema.string(
              description:
                  'Flutter project directory. Defaults to the MCP server working directory.',
            ),
            'deviceId': JsonSchema.string(
              description:
                  'Device id from list_devices. Optional only when exactly one supported device is connected.',
            ),
            'name': JsonSchema.string(
              description: 'Stable app id used later as the app argument.',
            ),
            'target': JsonSchema.string(
              description:
                  'Entrypoint passed as flutter run --target. Optional.',
            ),
            'timeout': JsonSchema.integer(
              description:
                  'Seconds to wait for the VM service and DTD. Default is 90. Increase it for a cold Gradle build.',
            ),
            'args': JsonSchema.array(
              description:
                  'Extra flutter run arguments. Allowed flags: --debug, --profile, --release, --flavor, --dart-define, --target, --device-id.',
              items: JsonSchema.string(),
            ),
          },
        ),
        callback: (args, extra) async {
          try {
            final timeout = args['timeout'];
            final summary = await runs.launch(
              directory:
                  (args['directory'] as String?)?.trim().isNotEmpty == true
                      ? args['directory'] as String
                      : Directory.current.path,
              deviceId: args['deviceId'] as String?,
              name: args['name'] as String?,
              target: args['target'] as String?,
              timeoutSeconds: timeout is num ? timeout.toInt() : 90,
              extraArgs: _stringArgs(args['args']),
            );
            return CallToolResult(content: [TextContent(text: summary)]);
          } catch (err) {
            _logger.warning('Failed to launch app', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to launch app: $err')],
            );
          }
        },
      )
      ..registerTool(
        'stop_app',
        description:
            'Stops a flutter run process started by launch_app and drops its session. The app process on the device stays in the foreground. With several launched apps, pass app.',
        annotations: const ToolAnnotations(title: 'Stop App'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          try {
            final summary = await runs.stop(args['app'] as String?);
            return CallToolResult(content: [TextContent(text: summary)]);
          } catch (err) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Failed to stop app: $err')],
            );
          }
        },
      )
      ..registerTool(
        'get_app_logs',
        description:
            'Reads the trailing output of a flutter run process started by launch_app. This is the flutter tool log, separate from get_logs, which reads logs captured inside the app. With several launched apps, pass app.',
        annotations: const ToolAnnotations(
          title: 'Get Flutter Run Logs',
          readOnlyHint: true,
        ),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'lines': JsonSchema.integer(
              description: 'How many trailing lines to return. Default is 500.',
            ),
          },
        ),
        callback: (args, extra) async {
          try {
            final lines = args['lines'];
            final text = runs.logs(
              args['app'] as String?,
              lines: lines is num ? lines.toInt() : 500,
            );
            return CallToolResult(content: [TextContent(text: text)]);
          } catch (err) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Interactive elements inspection
      ..registerTool(
        'get_interactive_elements',
        description:
            'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(
          title: 'Get Interactive Elements',
          readOnlyHint: true,
          idempotentHint: true,
        ),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Getting interactive elements');

          try {
            final response =
                await (await _connector(args)).getInteractiveElements();
            final elements = response['elements'] as List<dynamic>;

            // Format the elements nicely
            final buffer = StringBuffer()
              ..writeln('Found ${elements.length} interactive element(s):\n');

            for (final element in elements) {
              buffer.writeln(_formatElement(element as Map<String, dynamic>));
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } catch (err) {
            _logger.warning('Failed to get interactive elements', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Tap interaction
      ..registerTool(
        'tap',
        description:
            'Simulates a tap gesture on an element in the Flutter app that matches the given criteria. You can match elements by their key (a ValueKey<String>), by their text content (but not accessibility!), by their widget type, or by screen coordinates. Only one matching method should be used: either key, text, type, or coordinates. Prefer using the key if available, as it is more reliable. Limit yourself to elements from get_interactive_elements only if you can. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Tap Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to tap. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to tap. Use this for elements that display text like buttons or labels.',
            ),
            'type': JsonSchema.string(
              description:
                  'The widget type name of the element to tap (e.g., "ElevatedButton", "IconButton"). Use this to match elements by their Flutter widget type.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to tap at. Use this to tap at a specific position on the screen.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Tapping with matcher: $matcher');

          try {
            final response = await (await _connector(args)).tap(matcher);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [TextContent(text: message ?? 'Successfully tapped')],
            );
          } catch (err) {
            _logger.warning('Failed to tap', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Text input
      ..registerTool(
        'enter_text',
        description:
            'Enters text into a text field in the Flutter app that matches the given criteria. This simulates typing text into the field. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Enter Text'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'input': JsonSchema.string(
              description: 'The text to enter into the text field.',
            ),
            'key': JsonSchema.string(
              description:
                  'The key of the text field. You can get the key of an element by calling get_interactive_elements.',
            ),
          },
          required: ['input', 'key'],
        ),
        callback: (args, extra) async {
          final input = args['input'] as String;
          final matcher = _buildMatcher(args);
          _logger.info('Entering text into element with matcher: $matcher');

          try {
            final response =
                await (await _connector(args)).enterText(matcher, input);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Successfully entered text'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to enter text', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Scroll to element
      ..registerTool(
        'scroll_to',
        description:
            'Scrolls the view until an element matching the given criteria becomes visible. You can match elements by their key (a ValueKey<String>) or by their visible text content. This is useful when you need to interact with elements that are not currently visible on screen. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Scroll to Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to scroll to. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to scroll to.',
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Scrolling to element with matcher: $matcher');

          try {
            final response =
                await (await _connector(args)).scrollToElement(matcher);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(
                  text: message ?? 'Successfully scrolled to element',
                ),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to scroll to element', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Get logs
      ..registerTool(
        'get_logs',
        description:
            'Retrieves all application logs collected from the Flutter app since connection or since the last log retrieval. This includes debug messages, errors, and other log output from the running app. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(
          title: 'Get Application Logs',
          readOnlyHint: true,
        ),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Getting application logs');

          try {
            final response = await (await _connector(args)).getLogs();
            final logs = response['logs'] as List;
            final count = response['count'] as int;

            if (count == 0) {
              return CallToolResult(
                content: [const TextContent(text: 'No logs collected')],
              );
            }

            // Format logs nicely
            final buffer = StringBuffer()
              ..writeln(
                'Collected $count log entr${count == 1 ? 'y' : 'ies'}:\n',
              );

            for (final log in logs) {
              buffer.writeln(log);
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } catch (err) {
            _logger.warning('Failed to get logs', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Get rebuild snapshot (repaint monitoring)
      ..registerTool(
        'get_rebuild_snapshot',
        description:
            'Retrieves the current rebuild/repaint snapshot from the Flutter app, including: frame count, total rebuild count, average rebuilds per frame, and a ranked list of top widgets by rebuild count (重绘热点). Each entry shows widget type, key (if any), rebuild count, and percentage. Use this to locate which widgets are being rebuilt most frequently and identify unnecessary setState/rebuild hotspots in the code. Pass app when more than one app is connected. Requires that the app was started with enableGlobalRebuildHook (e.g. FlutterCopilotConfiguration(enableGlobalRebuildHook: true)). On Web platform, total and top will always be empty because BuildOwner hook cannot be injected. If tracking is not enabled, returns a message explaining how to enable it.',
        annotations: const ToolAnnotations(
          title: 'Get Rebuild Snapshot',
          readOnlyHint: true,
        ),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'topLimit': JsonSchema.integer(
              description:
                  'Maximum number of top-rebuild widgets to return (default: 20).',
            ),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Getting rebuild snapshot');

          try {
            final topLimit = args['topLimit'] is int
                ? args['topLimit'] as int
                : (args['topLimit'] is num
                        ? (args['topLimit'] as num).toInt()
                        : null) ??
                    20;
            final response = await (await _connector(args))
                .getRebuildSnapshot(topLimit: topLimit);

            if (response['status'] != 'Success') {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text: response['error']?.toString() ?? 'Unknown error',
                  ),
                ],
              );
            }

            final enabled = response['enabled'] as bool? ?? false;
            if (!enabled) {
              return CallToolResult(
                content: [
                  TextContent(
                    text: response['message']?.toString() ??
                        'Rebuild tracking is not enabled (enableGlobalRebuildHook is false).',
                  ),
                ],
              );
            }

            final frame = response['frame'] as int? ?? 0;
            final total = response['total'] as int? ?? 0;
            final top = response['top'] as List<dynamic>? ?? [];
            final avgPerFrame =
                frame > 0 ? (total / frame).toStringAsFixed(1) : '0.0';

            final buffer = StringBuffer()
              ..writeln('=== 重绘快照 (Rebuild Snapshot) ===')
              ..writeln('')
              ..writeln('帧数 (frames): $frame')
              ..writeln('总重建次数 (total rebuilds): $total')
              ..writeln('平均每帧重建 (avg rebuilds/frame): $avgPerFrame')
              ..writeln('');

            if (top.isEmpty) {
              buffer.writeln(
                '暂无重建数据。可能原因：\n'
                '  - 应用刚启动，尚未产生足够重建\n'
                '  - 当前为 Web 平台，不支持 BuildOwner hook\n'
                '  - enableGlobalRebuildHook 未开启',
              );
            } else {
              buffer.writeln(
                '--- 重绘热点排行 (Top ${top.length} Rebuild Hotspots) ---',
              );
              buffer.writeln(
                '排名  组件                                    重建次数   占比',
              );
              buffer.writeln(
                '----  ------                                  --------   ----',
              );

              for (var i = 0; i < top.length; i++) {
                final map = top[i] as Map<String, dynamic>;
                final type = map['type'] as String? ?? '?';
                final key = map['key'] as String?;
                final count = map['count'] as int? ?? 0;
                final percent = map['percent'] as String? ?? '0.0';
                final keyPart = key != null && key.isNotEmpty ? '#$key' : '';
                final widget = '$type$keyPart';
                // Pad for alignment
                final rank = '#${i + 1}'.padRight(6);
                final widgetPad = widget.length > 40
                    ? widget.substring(0, 37) + '...'
                    : widget.padRight(40);
                final countPad = count.toString().padLeft(8);
                final pctPad = '$percent%'.padLeft(6);
                buffer.writeln('$rank$widgetPad$countPad $pctPad');
              }

              buffer.writeln('');
              buffer
                  .writeln('提示：排名靠前的组件即为重绘热点，建议优先在代码中检查对应 Widget 的 setState 调用，'
                      '考虑拆分粒度、使用 const 构造、或将频繁变化的状态下移到子 Widget。');
            }

            return CallToolResult(
              content: [TextContent(text: buffer.toString())],
            );
          } catch (err) {
            _logger.warning('Failed to get rebuild snapshot', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Take screenshots
      ..registerTool(
        'take_screenshots',
        description:
            'Takes screenshots of all views in the Flutter app. Returns base64-encoded PNG images that can be decoded and saved. This captures the current visual state of the app. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(
          title: 'Take Screenshots',
          readOnlyHint: true,
        ),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Taking screenshots');

          try {
            final response = await (await _connector(args)).takeScreenshots();
            final screenshots =
                (response['screenshots'] as List<dynamic>).cast<String>();

            if (screenshots.isEmpty) {
              return CallToolResult(
                content: [const TextContent(text: 'No screenshots captured')],
              );
            } else {
              return CallToolResult(
                content: screenshots
                    .map(
                      (screenshot) =>
                          ImageContent(data: screenshot, mimeType: 'image/png'),
                    )
                    .toList(),
              );
            }
          } catch (err) {
            _logger.warning('Failed to take screenshots', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Hot reload
      ..registerTool(
        'hot_reload',
        description:
            'Performs a hot reload of the Flutter app. This reloads the Dart code without restarting the app, preserving the current state. Useful after making code changes to see them reflected in the running app. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Hot Reload'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
          },
        ),
        callback: (args, extra) async {
          _logger.info('Performing hot reload');

          try {
            final reloaded = await (await _connector(args)).hotReload();

            if (reloaded) {
              return CallToolResult(
                content: [
                  const TextContent(text: 'Hot reload completed successfully'),
                ],
              );
            } else {
              return CallToolResult(
                isError: true,
                content: [
                  TextContent(
                    text: 'Hot reload failed. The app may need a full restart.',
                  ),
                ],
              );
            }
          } catch (err) {
            _logger.warning('Failed to perform hot reload', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Hot reload failed: $err')],
            );
          }
        },
      )
      // Drag interaction
      ..registerTool(
        'flutter_copilot_drag',
        description:
            'Simulates a drag gesture on an element in the Flutter app. You can drag an element by its key, text, type, or coordinates. The drag can be specified either by deltaX/deltaY (relative movement) or by from/to coordinates (absolute positions). Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Drag Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to drag. You can get the key of an element by calling get_interactive_elements. Use this with deltaX/deltaY for relative drag.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to drag. Use this with deltaX/deltaY for relative drag.',
            ),
            'type': JsonSchema.string(
              description:
                  'The widget type name of the element to drag (e.g., "Slider", "Draggable"). Use this with deltaX/deltaY for relative drag.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to start drag from. Use this with deltaX/deltaY for relative drag from a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
            'deltaX': JsonSchema.number(
              description:
                  'The horizontal distance to drag (positive = right, negative = left). Use with key/text/type/coordinates for relative drag.',
            ),
            'deltaY': JsonSchema.number(
              description:
                  'The vertical distance to drag (positive = down, negative = up). Use with key/text/type/coordinates for relative drag.',
            ),
            'from': JsonSchema.object(
              description:
                  'Starting coordinates for absolute drag. Must be used together with "to".',
              properties: {
                'x': JsonSchema.number(description: 'Starting x coordinate'),
                'y': JsonSchema.number(description: 'Starting y coordinate'),
              },
              required: ['x', 'y'],
            ),
            'to': JsonSchema.object(
              description:
                  'Ending coordinates for absolute drag. Must be used together with "from".',
              properties: {
                'x': JsonSchema.number(description: 'Ending x coordinate'),
                'y': JsonSchema.number(description: 'Ending y coordinate'),
              },
              required: ['x', 'y'],
            ),
            // Compatibility parameter for Cursor MCP client
            'from_uid': JsonSchema.string(
              description:
                  'Compatibility parameter: The key of the element to drag (same as "key"). This is provided for compatibility with Cursor MCP client.',
            ),
          },
        ),
        callback: (args, extra) async {
          _logger
              .info('[flutter-copilot-mcp] Drag tool called with args: $args');

          // Handle compatibility parameters: from_uid -> key
          if (args.containsKey('from_uid') && !args.containsKey('key')) {
            _logger.info(
                '[flutter-copilot-mcp] Converting from_uid to key: ${args['from_uid']}');
            args['key'] = args['from_uid'];
          }

          // Validate that we have either (matcher + deltaX/deltaY) or (from + to)
          final hasMatcher = args.containsKey('key') ||
              args.containsKey('text') ||
              args.containsKey('type') ||
              args.containsKey('coordinates');
          final hasDelta =
              args.containsKey('deltaX') || args.containsKey('deltaY');
          final hasFrom = args.containsKey('from');
          final hasTo = args.containsKey('to');

          if (!hasFrom && !hasTo && !hasMatcher) {
            _logger.warning(
                '[flutter-copilot-mcp] Invalid drag parameters: no matcher or coordinates provided');
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '[flutter-copilot-mcp] Error: Must provide either (key/text/type/coordinates + deltaX/deltaY) or (from + to) for drag operation.',
                ),
              ],
            );
          }

          if (hasFrom && !hasTo) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '[flutter-copilot-mcp] Error: "from" must be used together with "to" for absolute drag.',
                ),
              ],
            );
          }

          if (hasTo && !hasFrom) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '[flutter-copilot-mcp] Error: "to" must be used together with "from" for absolute drag.',
                ),
              ],
            );
          }

          if (hasMatcher && !hasDelta && !hasFrom) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '[flutter-copilot-mcp] Error: When using key/text/type/coordinates, must also provide deltaX/deltaY for relative drag.',
                ),
              ],
            );
          }

          final matcher = _buildMatcher(args);
          final params = <String, dynamic>{};

          // Handle deltaX/deltaY - ensure they are numbers
          if (args.containsKey('deltaX')) {
            params['deltaX'] = _parseDouble(args['deltaX']) ?? 0.0;
          }
          if (args.containsKey('deltaY')) {
            params['deltaY'] = _parseDouble(args['deltaY']) ?? 0.0;
          }

          // Handle from/to coordinates
          if (args['from'] case final Map<String, dynamic> from) {
            params['fromX'] = from['x'];
            params['fromY'] = from['y'];
          }
          if (args['to'] case final Map<String, dynamic> to) {
            params['toX'] = to['x'];
            params['toY'] = to['y'];
          }

          _logger.info(
              '[flutter-copilot-mcp] Dragging with matcher: $matcher, params: $params');

          try {
            final response =
                await (await _connector(args)).drag(matcher, params);
            final message = response['message'] as String?;

            _logger.info(
                '[flutter-copilot-mcp] Drag completed successfully: $message');
            return CallToolResult(
              content: [
                TextContent(
                    text:
                        '[flutter-copilot-mcp] ${message ?? 'Successfully dragged'}')
              ],
            );
          } catch (err) {
            _logger.warning('[flutter-copilot-mcp] Failed to drag', err);
            return CallToolResult(
              isError: true,
              content: [
                TextContent(text: '[flutter-copilot-mcp] Drag failed: $err')
              ],
            );
          }
        },
      )
      // Swipe interaction
      ..registerTool(
        'swipe',
        description:
            'Simulates a swipe gesture on an element in the Flutter app. You can swipe an element by its key, text, type, or coordinates. The swipe direction can be left, right, up, or down. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Swipe Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to swipe. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description: 'The visible text content of the element to swipe.',
            ),
            'type': JsonSchema.string(
              description:
                  'The widget type name of the element to swipe (e.g., "PageView", "ListView").',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to swipe from. Use this to swipe from a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
            'direction': JsonSchema.string(
              description:
                  'The swipe direction. Must be one of: left, right, up, down.',
            ),
            'distance': JsonSchema.number(
              description:
                  'The swipe distance in pixels. Default is 200 pixels.',
            ),
          },
          required: ['direction'],
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          final direction =
              args['direction'] is String ? args['direction'] as String : null;
          if (direction == null) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text:
                      '[flutter-copilot-mcp] Error: Missing required parameter: direction',
                ),
              ],
            );
          }
          final distance = _parseDouble(args['distance']);

          _logger.info(
            'Swiping with matcher: $matcher, direction: $direction, distance: $distance',
          );

          try {
            final response = await (await _connector(args))
                .swipe(matcher, direction, distance);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Successfully swiped'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to swipe', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Long press interaction
      ..registerTool(
        'long_press',
        description:
            'Simulates a long press gesture on an element in the Flutter app. You can match elements by their key (a ValueKey<String>), by their text content, by their widget type, or by screen coordinates. The long press duration can be customized. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Long Press Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to long press. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to long press.',
            ),
            'type': JsonSchema.string(
              description: 'The widget type name of the element to long press.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to long press at. Use this to long press at a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
            'duration': JsonSchema.number(
              description:
                  'The duration of the long press in milliseconds. Default is 500ms.',
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          final duration = (args['duration'] as num?)?.toInt();
          _logger.info(
              'Long pressing with matcher: $matcher, duration: $duration');

          try {
            final response =
                await (await _connector(args)).longPress(matcher, duration);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Successfully long pressed'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to long press', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Double tap interaction
      ..registerTool(
        'double_tap',
        description:
            'Simulates a double tap gesture on an element in the Flutter app. You can match elements by their key (a ValueKey<String>), by their text content, by their widget type, or by screen coordinates. Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Double Tap Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'key': JsonSchema.string(
              description:
                  'The key of the element to double tap. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description:
                  'The visible text content of the element to double tap.',
            ),
            'type': JsonSchema.string(
              description: 'The widget type name of the element to double tap.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to double tap at. Use this to double tap at a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description:
                      'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Double tapping with matcher: $matcher');

          try {
            final response = await (await _connector(args)).doubleTap(matcher);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Successfully double tapped'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to double tap', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      )
      // Navigate
      ..registerTool(
        'navigate',
        description:
            'Controls app navigation. Supports push (navigate to a new route), pop (go back), replace (replace current route), pushReplacement (push and replace), and popUntil (pop until a specific route). Pass app when more than one app is connected.',
        annotations: const ToolAnnotations(title: 'Navigate'),
        inputSchema: ToolInputSchema(
          properties: {
            'app': JsonSchema.string(description: appParameterDescription),
            'action': JsonSchema.string(
              description:
                  'The navigation action to perform. Must be one of: push, pop, replace, pushReplacement, popUntil.',
            ),
            'route': JsonSchema.string(
              description:
                  'The route name. Required for push, replace, and pushReplacement actions. Optional for popUntil (if not provided, pops to root).',
            ),
            'arguments': JsonSchema.object(
              description:
                  'Optional arguments to pass to the route. Only used for push, replace, and pushReplacement actions.',
            ),
          },
          required: ['action'],
        ),
        callback: (args, extra) async {
          final action = args['action'] as String;
          final route = args['route'] as String?;
          final arguments = args['arguments'] as Map<String, dynamic>?;

          _logger.info(
            'Navigating with action: $action, route: $route, arguments: $arguments',
          );

          try {
            final response = await (await _connector(args))
                .navigate(action, route, arguments);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(
                    text: message ?? 'Navigation completed successfully'),
              ],
            );
          } catch (err) {
            _logger.warning('Failed to navigate', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: err.toString())],
            );
          }
        },
      );
  }

  /// Builds a widget matcher map from tool arguments.
  Map<String, dynamic> _buildMatcher(Map<String, dynamic> args) {
    final matcher = <String, dynamic>{};
    // Flatten coordinates for VM service (which only supports string->string)
    if (args['coordinates'] case final Map<String, dynamic> coordinates) {
      matcher['x'] = coordinates['x'];
      matcher['y'] = coordinates['y'];
    }
    if (args.containsKey('key')) {
      matcher['key'] = args['key'];
    }
    if (args.containsKey('text')) {
      matcher['text'] = args['text'];
    }
    if (args.containsKey('type')) {
      matcher['type'] = args['type'];
    }
    return matcher;
  }

  /// Formats an element for display.
  String _formatElement(Map<String, dynamic> element) {
    final buffer = StringBuffer();

    // Element type
    if (element['type'] != null) {
      buffer.write('Type: ${element['type']}');
    }

    // Key
    if (element['key'] != null) {
      buffer.write(', Key: "${element['key']}"');
    }

    // Text content
    if (element['text'] != null && element['text'] != '') {
      buffer.write(', Text: "${element['text']}"');
    }

    // Additional properties
    final additionalProps = <String>[];
    element.forEach((key, value) {
      if (key != 'type' && key != 'key' && key != 'text' && value != null) {
        additionalProps.add('$key: ${_formatValue(value)}');
      }
    });

    if (additionalProps.isNotEmpty) {
      buffer.write(', ${additionalProps.join(', ')}');
    }

    return buffer.toString();
  }

  /// Formats a value for display.
  String _formatValue(dynamic value) {
    if (value is String) {
      return '"$value"';
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }

  List<String> _stringArgs(Object? value) {
    if (value == null) return const [];
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    throw FormatException('args must be a list of strings');
  }

  /// Parses a value to double, handling both num and String types.
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
