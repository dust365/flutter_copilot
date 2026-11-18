import 'dart:io';
import 'package:flutter_copilot_mcp/src/session/session_server.dart';

Future<void> main(List<String> args) async {
  exitCode = await runSessionDaemon(args);
}
