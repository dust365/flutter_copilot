import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart' as logging;
import 'package:flutter_copilot_mcp/src/compat/copilot_stdio_server_transport.dart';
import 'package:flutter_copilot_mcp/src/version.g.dart';
import 'package:flutter_copilot_mcp/src/vm_service/vm_service_context.dart';
import 'package:mcp_dart/mcp_dart.dart';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.')
    ..addOption(
      'log-level',
      abbr: 'l',
      defaultsTo: 'INFO',
      help: 'Log level (FINEST, FINER, FINE, CONFIG, INFO, WARNING, SEVERE).',
    )
    ..addOption(
      'log-file',
      help: 'Path to log file. If not set, logs to stderr.',
    )
    ..addOption(
      'sse-port',
      help: 'Port for SSE server. If not set, uses stdio transport.',
    );
}

void printUsage(ArgParser argParser) {
  stderr
    ..writeln(
        'Flutter Copilot MCP Server - Flutter app interaction for AI agents')
    ..writeln()
    ..writeln('Usage: flutter_copilot_mcp [options]')
    ..writeln()
    ..writeln('Options:')
    ..writeln(argParser.usage);
}

Future<int> main(List<String> arguments) async {
  final argParser = buildParser();
  try {
    final results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return 0;
    }
    if (results.flag('version')) {
      stderr.writeln('flutter_copilot_mcp version: $version');
      return 0;
    }

    final logLevelName = (results.option('log-level') ?? 'INFO').toUpperCase();
    final logFile = results.option('log-file');
    final ssePortStr = results.option('sse-port');
    final ssePort = ssePortStr != null ? int.tryParse(ssePortStr) : null;

    setupLogging(logLevelName, logFile);

    final vmService = VmServiceContext();

    final server = McpServer(
      const Implementation(name: 'flutter-copilot-mcp', version: version),
      options: const McpServerOptions(
        capabilities: ServerCapabilities(tools: ServerCapabilitiesTools()),
        instructions: '''
Flutter Copilot MCP drives Flutter apps that include flutter_copilot_claw and are running in debug mode. One server holds every connected device.

Find apps:
1. Call list_dtds, then connect_dtd with a local ws:// URI from that list. Every registered app that initialized Flutter Copilot is connected. Apps that appear later on the same DTD are connected automatically, and a restarted app keeps its name.
2. Or call list_devices, then launch_app. launch_app starts flutter run and connects that device before it returns. Call it once per device. Same-target devices (two Android, two iOS, or two of the same desktop OS) must be launched one after another; different targets can be launched together.
3. connect is only for a ws:// DDS address you already have. It adds a session and does not replace the others.

Call list_apps to see ids. When more than one app is connected, pass app on every other tool. When only one app is connected, app can be omitted.

stop_app ends a flutter run this server started. The app on the device stays open. disconnect only drops the session.

Use get_interactive_elements before tapping. Prefer a ValueKey. After code changes, call hot_reload on that app.
''',
      ),
    );

    vmService.registerTools(server);

    if (ssePort != null) {
      return await runSseServer(server, vmService, ssePort);
    } else {
      return await runStdioServer(server, vmService);
    }
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln();
    printUsage(argParser);
    return 1;
  } on Exception catch (e) {
    stderr.writeln(e.toString());
    return 1;
  }
}

void setupLogging(String logLevelName, String? logFile) {
  final logLevel = logging.Level.LEVELS.firstWhere(
    (e) => e.name == logLevelName,
    orElse: () => logging.Level.INFO,
  );

  logging.Logger.root.level = logLevel;

  if (logFile != null) {
    final file = File(logFile)..createSync(recursive: true);
    logging.Logger.root.onRecord.listen((record) {
      file.writeAsStringSync(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}\n',
        mode: FileMode.append,
      );
    });
  } else {
    logging.Logger.root.onRecord.listen((record) {
      stderr.writeln(
        '[${record.level.name}][${record.loggerName}][${_formatTime(record.time)}] ${record.message}',
      );
    });
  }
}

String _formatTime(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

Future<int> runStdioServer(McpServer server, VmServiceContext vmService) async {
  final logger = logging.Logger('main');

  // Use a stdio transport with small compatibility fixes for clients like Copilot.
  final transport = CopilotCompatStdioServerTransport();

  try {
    logger.fine('Running MCP server on stdio');
    await server.connect(transport);
    logger.info('Server started');
  } catch (e, st) {
    logger.severe('Error when starting the Stdio transport', e, st);
    return 1;
  }

  final signal = await _ExitSignal().wait;
  logger.info('Received ${signal.name}, stopping');

  await vmService.close();
  await server.close();
  await transport.close();
  logger.info('Stopped');
  return 0;
}

Future<int> runSseServer(
  McpServer server,
  VmServiceContext vmService,
  int ssePort,
) async {
  final logger = logging.Logger('main');
  final sseServerManager = SseServerManager(server);
  try {
    final httpServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      ssePort,
    );
    logger.fine('Running MCP server on SSE port $ssePort');
    unawaited(
      _ExitSignal().wait.then((signal) {
        logger.info('Received ${signal.name}, stopping');
        unawaited(httpServer.close());
      }),
    );

    await for (final request in httpServer) {
      unawaited(sseServerManager.handleRequest(request));
    }

    logger.info('Stopping');
    await vmService.close();
    await server.close();
  } catch (e, st) {
    logger.severe('Error when waiting for MCP client connection', e, st);
    return 1;
  }

  logger.info('Stopped');
  return 0;
}

class _ExitSignal {
  _ExitSignal() {
    // SIGTERM is not supported on Windows, only listen on non-Windows platforms
    if (!Platform.isWindows) {
      _sigtermSubscription = ProcessSignal.sigterm.watch().listen(
            _handleSignal,
          );
    }
    _sigintSubscription = ProcessSignal.sigint.watch().listen(_handleSignal);
  }

  final _completer = Completer<ProcessSignal>();
  StreamSubscription<ProcessSignal>? _sigtermSubscription;
  late final StreamSubscription<ProcessSignal> _sigintSubscription;

  Future<ProcessSignal> get wait => _completer.future;

  void _handleSignal(ProcessSignal signal) {
    if (!_completer.isCompleted) {
      _completer.complete(signal);
      _cleanup();
    }
  }

  void _cleanup() {
    _sigtermSubscription?.cancel();
    _sigintSubscription.cancel();
  }
}
