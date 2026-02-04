import 'dart:convert';

import 'package:logging/logging.dart' as logging;
import 'package:flutter_copilot_mcp/src/vm_service/vm_service_connector.dart';
import 'package:mcp_dart/mcp_dart.dart';

/// Context for managing VM service connection and registering MCP tools.
final class VmServiceContext {
  VmServiceContext()
      : connector = VmServiceConnector(),
        _logger = logging.Logger('VmServiceContext');

  final VmServiceConnector connector;
  final logging.Logger _logger;

  /// Registers all VM service related tools with the MCP server.
  void registerTools(McpServer server) {
    // Connection management tools
    server
      ..registerTool(
        'connect',
        description:
            'Connects to a Flutter app via its VM service URI. This must be called before using any other tools. The VM service URI is typically in the format ws://127.0.0.1:PORT/ws and can be found in the Flutter app output when running in debug mode.',
        annotations: const ToolAnnotations(title: 'Connect to App'),
        inputSchema: ToolInputSchema(
          properties: {
            'uri': JsonSchema.string(
              description:
                  'VM service URI (e.g., ws://127.0.0.1:8181/ws). This is printed in the Flutter app console when running in debug mode.',
            ),
          },
          required: ['uri'],
        ),
        callback: (args, extra) async {
          final uri = args['uri'] as String;
          _logger.info('Connecting to app at $uri');

          try {
            await connector.connect(uri);
            return CallToolResult(
              content: [
                TextContent(text: 'Successfully connected to app at $uri'),
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
            'Disconnects from the currently connected Flutter app. After disconnecting, you must call connect again to use any other tools.',
        annotations: const ToolAnnotations(title: 'Disconnect from App'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Disconnecting from app');

          try {
            await connector.disconnect();
            return CallToolResult(
              content: [
                const TextContent(text: 'Successfully disconnected from app'),
              ],
            );
          } catch (err) {
            _logger.severe('Error during disconnect', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Error during disconnect: $err')],
            );
          }
        },
      )
      // Interactive elements inspection
      ..registerTool(
        'get_interactive_elements',
        description:
            'Returns a list of all interactive elements currently visible in the Flutter app UI tree. Each element includes its type, text content (if any), key (if any), and other identifying properties. This is useful for understanding what can be interacted with in the app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Get Interactive Elements',
          readOnlyHint: true,
          idempotentHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Getting interactive elements');

          try {
            final response = await connector.getInteractiveElements();
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
            'Simulates a tap gesture on an element in the Flutter app that matches the given criteria. You can match elements by their key (a ValueKey<String>), by their text content (but not accessibility!), by their widget type, or by screen coordinates. Only one matching method should be used: either key, text, type, or coordinates. Prefer using the key if available, as it is more reliable. Limit yourself to elements from get_interactive_elements only if you can. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Tap Element'),
        inputSchema: ToolInputSchema(
          properties: {
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
                  description: 'The x coordinate (horizontal position from left).',
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
            final response = await connector.tap(matcher);
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
            'Enters text into a text field in the Flutter app that matches the given criteria. This simulates typing text into the field. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Enter Text'),
        inputSchema: ToolInputSchema(
          properties: {
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
            final response = await connector.enterText(matcher, input);
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
            'Scrolls the view until an element matching the given criteria becomes visible. You can match elements by their key (a ValueKey<String>) or by their visible text content. This is useful when you need to interact with elements that are not currently visible on screen. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Scroll to Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'key': JsonSchema.string(
              description:
                  'The key of the element to scroll to. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description: 'The visible text content of the element to scroll to.',
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          _logger.info('Scrolling to element with matcher: $matcher');

          try {
            final response = await connector.scrollToElement(matcher);
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
            'Retrieves all application logs collected from the Flutter app since connection or since the last log retrieval. This includes debug messages, errors, and other log output from the running app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Get Application Logs',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Getting application logs');

          try {
            final response = await connector.getLogs();
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
      // Take screenshots
      ..registerTool(
        'take_screenshots',
        description:
            'Takes screenshots of all views in the Flutter app. Returns base64-encoded PNG images that can be decoded and saved. This captures the current visual state of the app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(
          title: 'Take Screenshots',
          readOnlyHint: true,
        ),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Taking screenshots');

          try {
            final response = await connector.takeScreenshots();
            final screenshots = (response['screenshots'] as List<dynamic>).cast<String>();

            if (screenshots.isEmpty) {
              return CallToolResult(
                content: [const TextContent(text: 'No screenshots captured')],
              );
            } else {
              return CallToolResult(
                content: screenshots
                    .map(
                      (screenshot) => ImageContent(data: screenshot, mimeType: 'image/png'),
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
            'Performs a hot reload of the Flutter app. This reloads the Dart code without restarting the app, preserving the current state. Useful after making code changes to see them reflected in the running app. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Hot Reload'),
        inputSchema: const ToolInputSchema(properties: {}),
        callback: (args, extra) async {
          _logger.info('Performing hot reload');

          try {
            final reloaded = await connector.hotReload();

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
            'Simulates a drag gesture on an element in the Flutter app. You can drag an element by its key, text, type, or coordinates. The drag can be specified either by deltaX/deltaY (relative movement) or by from/to coordinates (absolute positions). Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Drag Element'),
        inputSchema: ToolInputSchema(
          properties: {
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
                  description: 'The x coordinate (horizontal position from left).',
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
          _logger.info('[flutter-copilot-mcp] Drag tool called with args: $args');

          // Handle compatibility parameters: from_uid -> key
          if (args.containsKey('from_uid') && !args.containsKey('key')) {
            _logger.info('[flutter-copilot-mcp] Converting from_uid to key: ${args['from_uid']}');
            args['key'] = args['from_uid'];
          }

          // Validate that we have either (matcher + deltaX/deltaY) or (from + to)
          final hasMatcher = args.containsKey('key') ||
              args.containsKey('text') ||
              args.containsKey('type') ||
              args.containsKey('coordinates');
          final hasDelta = args.containsKey('deltaX') || args.containsKey('deltaY');
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

          _logger.info('[flutter-copilot-mcp] Dragging with matcher: $matcher, params: $params');

          try {
            final response = await connector.drag(matcher, params);
            final message = response['message'] as String?;

            _logger.info('[flutter-copilot-mcp] Drag completed successfully: $message');
            return CallToolResult(
              content: [
                TextContent(text: '[flutter-copilot-mcp] ${message ?? 'Successfully dragged'}')
              ],
            );
          } catch (err) {
            _logger.warning('[flutter-copilot-mcp] Failed to drag', err);
            return CallToolResult(
              isError: true,
              content: [TextContent(text: '[flutter-copilot-mcp] Drag failed: $err')],
            );
          }
        },
      )
      // Swipe interaction
      ..registerTool(
        'swipe',
        description:
            'Simulates a swipe gesture on an element in the Flutter app. You can swipe an element by its key, text, type, or coordinates. The swipe direction can be left, right, up, or down. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Swipe Element'),
        inputSchema: ToolInputSchema(
          properties: {
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
                  description: 'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
            'direction': JsonSchema.string(
              description: 'The swipe direction. Must be one of: left, right, up, down.',
            ),
            'distance': JsonSchema.number(
              description: 'The swipe distance in pixels. Default is 200 pixels.',
            ),
          },
          required: ['direction'],
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          final direction = args['direction'] is String ? args['direction'] as String : null;
          if (direction == null) {
            return CallToolResult(
              isError: true,
              content: [
                TextContent(
                  text: '[flutter-copilot-mcp] Error: Missing required parameter: direction',
                ),
              ],
            );
          }
          final distance = _parseDouble(args['distance']);

          _logger.info(
            'Swiping with matcher: $matcher, direction: $direction, distance: $distance',
          );

          try {
            final response = await connector.swipe(matcher, direction, distance);
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
            'Simulates a long press gesture on an element in the Flutter app. You can match elements by their key (a ValueKey<String>), by their text content, by their widget type, or by screen coordinates. The long press duration can be customized. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Long Press Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'key': JsonSchema.string(
              description:
                  'The key of the element to long press. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description: 'The visible text content of the element to long press.',
            ),
            'type': JsonSchema.string(
              description: 'The widget type name of the element to long press.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to long press at. Use this to long press at a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description: 'The x coordinate (horizontal position from left).',
                ),
                'y': JsonSchema.number(
                  description: 'The y coordinate (vertical position from top).',
                ),
              },
              required: ['x', 'y'],
            ),
            'duration': JsonSchema.number(
              description: 'The duration of the long press in milliseconds. Default is 500ms.',
            ),
          },
        ),
        callback: (args, extra) async {
          final matcher = _buildMatcher(args);
          final duration = (args['duration'] as num?)?.toInt();
          _logger.info('Long pressing with matcher: $matcher, duration: $duration');

          try {
            final response = await connector.longPress(matcher, duration);
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
            'Simulates a double tap gesture on an element in the Flutter app. You can match elements by their key (a ValueKey<String>), by their text content, by their widget type, or by screen coordinates. Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Double Tap Element'),
        inputSchema: ToolInputSchema(
          properties: {
            'key': JsonSchema.string(
              description:
                  'The key of the element to double tap. You can get the key of an element by calling get_interactive_elements.',
            ),
            'text': JsonSchema.string(
              description: 'The visible text content of the element to double tap.',
            ),
            'type': JsonSchema.string(
              description: 'The widget type name of the element to double tap.',
            ),
            'coordinates': JsonSchema.object(
              description:
                  'Screen coordinates to double tap at. Use this to double tap at a specific position.',
              properties: {
                'x': JsonSchema.number(
                  description: 'The x coordinate (horizontal position from left).',
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
            final response = await connector.doubleTap(matcher);
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
            'Controls app navigation. Supports push (navigate to a new route), pop (go back), replace (replace current route), pushReplacement (push and replace), and popUntil (pop until a specific route). Requires an active connection established via connect.',
        annotations: const ToolAnnotations(title: 'Navigate'),
        inputSchema: ToolInputSchema(
          properties: {
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
            final response = await connector.navigate(action, route, arguments);
            final message = response['message'] as String?;

            return CallToolResult(
              content: [
                TextContent(text: message ?? 'Navigation completed successfully'),
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

  /// Parses a value to double, handling both num and String types.
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
