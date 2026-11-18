import 'dart:async';

import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';
import 'package:flutter_copilot_mcp/src/vm_service/vm_service_connector.dart';

/// A process this server started and can still stop or read logs from.
abstract class OwnedProcess {
  String get id;
  String get deviceId;
  bool get isRunning;
  String logTail({int lines = 500});
  Future<void> stop();
}

/// One connected DDS, addressed by a stable [id].
class AppSession {
  AppSession({
    required this.id,
    required this.uri,
    required this.connector,
    this.deviceId,
    this.dtdUri,
    this.process,
    this.projectRoot,
    this.target,
    this.platform,
    this.displayName,
    this.flavor,
    this.mode = 'debug',
    this.launchArgs,
  });

  String id;
  String uri;
  String? deviceId;
  String? dtdUri;
  VmServiceConnector connector;
  OwnedProcess? process;
  String? projectRoot;
  String? target;
  String? platform;
  String? displayName;
  String? flavor;
  String mode;
  List<String>? launchArgs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'uri': uri,
        'name': displayName ?? id,
        'deviceId': deviceId,
        'projectRoot': projectRoot,
        'target': target,
        'platform': platform,
        'flavor': flavor,
        'mode': mode,
        'launchArgs': launchArgs,
        'owned': launched,
        'state': connector.isConnected ? 'connected' : 'disconnected',
      };

  bool get launched => process != null;

  String describe() {
    final parts = <String>[
      id,
      if (deviceId != null) 'device=$deviceId',
      if (launched) 'launched-by-server',
      uri,
    ];
    return parts.join('  ');
  }
}

/// Thrown when a tool cannot choose which connected app to use.
class AppSelectionException implements Exception {
  AppSelectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The in-memory table of DDS connections for this MCP process.
class AppDirectory {
  final List<AppSession> _sessions = [];
  final Map<String, Future<AppSession>> _connecting = {};
  int _nextId = 1;
  final String _epoch = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  bool _closed = false;

  /// Last `dart tooling-daemon --list` output, included when no app is connected.
  String? dtdListing;

  /// Invoked when a tool runs and the table is empty, so the error can include
  /// the DTDs currently on this machine.
  Future<String> Function()? listDtds;

  List<AppSession> get sessions => List.unmodifiable(_sessions);

  /// Selects a session.
  ///
  /// An empty [app] uses the only session. With several sessions [app] must
  /// match an id, a device id, or a VM service URI.
  AppSession resolve(String? app) {
    final query = app?.trim();
    if (_sessions.isEmpty) {
      throw AppSelectionException(_emptyMessage());
    }
    if (query == null || query.isEmpty) {
      if (_sessions.length == 1) return _sessions.single;
      throw AppSelectionException(
        'Multiple apps are connected. Pass app.\n$describeAll',
      );
    }

    final normalized = _tryNormalize(query);
    for (final session in _sessions) {
      if (session.id == query ||
          session.deviceId == query ||
          session.uri == query ||
          (normalized != null && session.uri == normalized)) {
        return session;
      }
    }
    throw AppSelectionException('No app matches "$query".\n$describeAll');
  }

  /// Like [resolve], but refreshes the DTD list first when nothing is connected.
  Future<AppSession> open(String? app) async {
    if (_sessions.isEmpty && listDtds != null) {
      try {
        dtdListing = await listDtds!();
      } catch (err) {
        dtdListing = err.toString();
      }
    }
    return resolve(app);
  }

  /// Connects [uri] and adds a session.
  ///
  /// Connecting a URI that is already in the table returns that session.
  /// When [replaceSameId] is set and [id] already belongs to a different URI,
  /// that session is pointed at the new URI. Otherwise a colliding id gets a
  /// suffix so two live apps are both kept.
  Future<AppSession> connectUri({
    required String uri,
    String? id,
    String? deviceId,
    String? dtdUri,
    OwnedProcess? process,
    bool replaceSameId = false,
    Duration? waitForExtension,
    String? projectRoot,
    String? target,
    String? displayName,
    String? flavor,
    String? mode,
    List<String>? launchArgs,
  }) async {
    final normalized = normalizeVmServiceUri(uri);
    final pending = _connecting[normalized];
    if (pending != null) {
      await pending;
    }
    final future = _connectUri(
      uri: normalized,
      id: id,
      deviceId: deviceId,
      dtdUri: dtdUri,
      process: process,
      replaceSameId: replaceSameId,
      waitForExtension: waitForExtension,
    );
    _connecting[normalized] = future;
    try {
      final session = await future;
      session.projectRoot = projectRoot ?? session.projectRoot;
      session.target = target ?? session.target;
      session.displayName = displayName ?? session.displayName;
      session.flavor = flavor ?? session.flavor;
      if (mode != null) session.mode = mode;
      session.launchArgs = launchArgs ?? session.launchArgs;
      return session;
    } finally {
      if (identical(_connecting[normalized], future))
        _connecting.remove(normalized);
    }
  }

  Future<AppSession> _connectUri({
    required String uri,
    String? id,
    String? deviceId,
    String? dtdUri,
    OwnedProcess? process,
    bool replaceSameId = false,
    Duration? waitForExtension,
  }) async {
    if (_closed) throw StateError('App directory is closed');
    final normalized = normalizeVmServiceUri(uri);
    final existing = _findByUri(normalized);
    if (existing != null) {
      if (deviceId != null) existing.deviceId = deviceId;
      if (dtdUri != null) existing.dtdUri = dtdUri;
      if (process != null) existing.process = process;
      return existing;
    }

    final base = (id == null || id.trim().isEmpty)
        ? 'app-$_epoch-${_nextId++}'
        : id.trim();
    final clash = _findById(base);
    if (clash != null && replaceSameId) {
      await _retarget(
        clash,
        normalized,
        deviceId: deviceId,
        dtdUri: dtdUri,
        process: process,
        waitForExtension: waitForExtension,
      );
      return clash;
    }

    final connector = VmServiceConnector();
    try {
      await connector.connect(normalized, waitForExtension: waitForExtension);
    } catch (err) {
      await connector.disconnect();
      rethrow;
    }

    Map<String, dynamic> metadata = {};
    try {
      metadata = await connector.describeApp();
    } catch (_) {
      // Explicit URI connections still work without optional runtime metadata.
    }
    if (_closed) {
      await connector.disconnect();
      throw StateError('App directory is closed');
    }
    final platform = metadata['platform'] as String?;
    final desktopDevice = switch (platform) {
      'macos' => 'macos',
      'linux' => 'linux',
      'windows' => 'windows',
      _ => null,
    };
    final session = AppSession(
      id: clash == null ? base : _suffixedId(base, normalized),
      uri: normalized,
      connector: connector,
      deviceId: deviceId ?? desktopDevice,
      dtdUri: dtdUri,
      process: process,
      projectRoot: metadata['projectRoot'] as String?,
      target: metadata['target'] as String?,
      platform: platform,
    );
    _bind(session, connector);
    _sessions.add(session);
    return session;
  }

  /// Drops the session selected by [app]. An owned `flutter run` is left running.
  Future<String> disconnectApp(String? app) async {
    if (_sessions.isEmpty && (app == null || app.trim().isEmpty)) {
      return 'No apps are connected.';
    }
    final session = resolve(app);
    final id = session.id;
    await removeSession(session);
    return 'Disconnected $id. '
        'A flutter run started by this server is still running until stop_app.';
  }

  Future<void> removeByUri(String uri) async {
    final normalized = _tryNormalize(uri) ?? uri.trim();
    final session = _findByUri(normalized);
    if (session == null) return;
    await removeSession(session);
  }

  Future<void> removeSession(
    AppSession session, {
    bool closeConnector = true,
  }) async {
    _sessions.remove(session);
    if (!closeConnector) return;
    session.connector.onDisconnected = null;
    await session.connector.disconnect();
  }

  /// Sessions that were discovered through [dtdUri].
  List<AppSession> sessionsForDtd(String dtdUri) {
    return _sessions.where((session) => session.dtdUri == dtdUri).toList();
  }

  Future<void> close() async {
    _closed = true;
    final copy = List<AppSession>.of(_sessions);
    for (final session in copy) {
      await removeSession(session);
    }
  }

  String get describeAll {
    if (_sessions.isEmpty) return 'No apps connected.';
    return _sessions.map((session) => '- ${session.describe()}').join('\n');
  }

  AppSession? _findByUri(String uri) {
    for (final session in _sessions) {
      if (session.uri == uri) return session;
    }
    return null;
  }

  AppSession? _findById(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  String _suffixedId(String base, String uri) {
    final port = Uri.tryParse(uri)?.port;
    final candidate = port == null || port == 0 ? '$base#2' : '$base#$port';
    if (_findById(candidate) == null) return candidate;
    return '$base#${_sessions.length + 1}';
  }

  void _bind(AppSession session, VmServiceConnector connector) {
    connector.onDisconnected = () {
      if (!_sessions.contains(session)) return;
      if (!identical(session.connector, connector)) return;
      unawaited(removeSession(session, closeConnector: false));
    };
  }

  Future<void> _retarget(
    AppSession session,
    String normalized, {
    String? deviceId,
    String? dtdUri,
    OwnedProcess? process,
    Duration? waitForExtension,
  }) async {
    final previous = session.connector;
    previous.onDisconnected = null;
    await previous.disconnect();

    final next = VmServiceConnector();
    try {
      await next.connect(normalized, waitForExtension: waitForExtension);
    } catch (err) {
      _sessions.remove(session);
      await next.disconnect();
      rethrow;
    }

    session
      ..connector = next
      ..uri = normalized;
    if (deviceId != null) session.deviceId = deviceId;
    if (dtdUri != null) session.dtdUri = dtdUri;
    if (process != null) session.process = process;
    _bind(session, next);
  }

  String _emptyMessage() {
    final buffer = StringBuffer(
      'No apps are connected. '
      'Call list_dtds and then connect_dtd, or call launch_app.',
    );
    final listing = dtdListing?.trim();
    if (listing != null && listing.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Current DTDs:')
        ..write(listing);
    }
    return buffer.toString();
  }

  String? _tryNormalize(String value) {
    try {
      return normalizeVmServiceUri(value);
    } on FormatException {
      return null;
    }
  }
}
