import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:flutter_copilot_mcp/src/session/session_engine.dart';
import 'package:flutter_copilot_mcp/src/session/session_error.dart';
import 'package:flutter_copilot_mcp/src/version.g.dart';
import 'package:path/path.dart' as p;

File sessionStateFile(String root, SdkTools sdk) {
  final key = sha256
      .convert(utf8.encode('$root\n${sdk.flutter}\n$version'))
      .toString()
      .substring(0, 16);
  return File(
      p.join(root, '.dart_tool', 'flutter_copilot', 'session-$key.json'));
}

/// Authenticated loopback IPC. The locator is not a stored VM service URI.
class SessionServer {
  SessionServer._(
      this.engine, this._server, this._lock, this._state, this.token);
  final SessionEngine engine;
  final HttpServer _server;
  final RandomAccessFile _lock;
  final File _state;
  final String token;
  late Timer _idle;
  bool _closing = false;
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  DateTime _lastRequest = DateTime.now();

  static Future<SessionServer?> start(SessionEngine engine,
      {File? state}) async {
    final file = state ?? sessionStateFile(engine.root, engine.sdk);
    await file.parent.create(recursive: true);
    final lock = await File('${file.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      return null; // Another process is already starting or owns this scope.
    }
    HttpServer? http;
    try {
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final token = base64UrlEncode(
          List.generate(32, (_) => Random.secure().nextInt(256)));
      final server = SessionServer._(engine, http, lock, file, token);
      final temporary = File('${file.path}.$pid.tmp');
      await temporary.writeAsString(
          jsonEncode({
            'protocol': 1,
            'version': version,
            'pid': pid,
            'root': engine.root,
            'flutter': engine.sdk.flutter,
            'url': 'http://127.0.0.1:${http.port}/rpc',
            'token': token,
          }),
          flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['600', temporary.path]);
      }
      await temporary.rename(file.path);
      http.listen((request) {
        unawaited(server._handle(request));
      });
      server._idle = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!engine.busy &&
            DateTime.now().difference(server._lastRequest) >
                const Duration(minutes: 15)) {
          unawaited(server.close());
        }
      });
      return server;
    } catch (_) {
      await http?.close(force: true);
      await lock.close();
      rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _lastRequest = DateTime.now();
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.method != 'POST' ||
        request.uri.path != '/rpc' ||
        request.headers.value(HttpHeaders.authorizationHeader) !=
            'Bearer $token' ||
        request.headers.value('origin') != null) {
      response.statusCode = HttpStatus.forbidden;
      await response.close();
      return;
    }
    dynamic id;
    try {
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 5))) {
        bytes.addAll(chunk);
        if (bytes.length > 65536)
          throw SessionError('invalid_request', 'Request exceeds 64 KiB');
      }
      final message = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      id = message['id'];
      final method = message['method'] as String;
      final params = Map<String, dynamic>.from(message['params'] as Map? ?? {});
      final dynamic result;
      if (method == 'shutdown') {
        if (engine.busy)
          throw SessionError('session_busy',
              'Stop or detach owned Apps before shutting down.');
        result = {'stopped': true};
        unawaited(
            Future<void>.delayed(const Duration(milliseconds: 100), close));
      } else {
        result = await engine.call(method, params);
      }
      response
          .write(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
    } catch (e) {
      final error =
          e is SessionError ? e : SessionError('session_error', e.toString());
      response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32000,
          'message': error.message,
          'data': error.toJson()
        }
      }));
    } finally {
      await response.close();
    }
  }

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _idle.cancel();
    await _server.close(force: true);
    await engine.close();
    try {
      final current = jsonDecode(await _state.readAsString()) as Map;
      if (current['token'] == token) await _state.delete();
    } on FileSystemException {/* State was removed by the user. */}
    await _lock.unlock();
    await _lock.close();
    _done.complete();
  }
}

Future<int> runSessionDaemon(List<String> args) async {
  final index = args.indexOf('--directory');
  if (index < 0 || index + 1 >= args.length) {
    stderr.writeln('Missing --directory for session daemon');
    return 64;
  }
  final root = projectDirectory(args[index + 1]);
  final sdk = SdkTools.forProject(root);
  final engine = SessionEngine(root: root, sdk: sdk);
  final server = await SessionServer.start(engine);
  if (server == null) {
    await engine.close();
    return 0;
  }
  final signals = <StreamSubscription<ProcessSignal>>[];
  Future<void> stop(ProcessSignal _) async {
    for (final signal in signals) {
      await signal.cancel();
    }
    await server.close();
  }

  signals.add(ProcessSignal.sigint.watch().listen(stop));
  if (!Platform.isWindows)
    signals.add(ProcessSignal.sigterm.watch().listen(stop));
  await server.done;
  for (final signal in signals) {
    await signal.cancel();
  }
  return 0;
}
