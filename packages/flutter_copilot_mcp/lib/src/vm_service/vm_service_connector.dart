import 'dart:async';
import 'dart:io';

import 'package:flutter_copilot_mcp/src/session/sdk_tools.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Thrown when hot restart is requested but `flutter run` has not registered
/// its `hotRestart` service.
class HotRestartUnavailableException implements Exception {
  const HotRestartUnavailableException();

  @override
  String toString() =>
      'hotRestart is not registered. Hot restart requires a debug '
      'flutter run process; the app alone cannot restart.';
}

/// Exception thrown when an operation is attempted without an active connection.
class NotConnectedException implements Exception {
  const NotConnectedException();

  @override
  String toString() =>
      'Not connected to any app. Call list_dtds and connect_dtd, or launch_app.';
}

/// The VM is up, but this isolate set has no Flutter Copilot extensions.
class NoCopilotExtensionException implements Exception {
  const NoCopilotExtensionException(this.uri);

  final String? uri;

  @override
  String toString() {
    final where = uri == null ? '' : ' at $uri';
    return 'No isolate found with ext.flutter.flutter_copilot.getLogs$where. '
        'Make sure the Flutter app has flutter_copilot_claw initialized.';
  }
}

/// Exception thrown when a VM service extension call fails.
class VmServiceExtensionException implements Exception {
  VmServiceExtensionException(this.message, this.error, this.stackTrace);

  final String message;
  final String? error;
  final String? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer.write('\nError: $error');
    }
    if (stackTrace != null) {
      buffer.write('\nStack trace: $stackTrace');
    }
    return buffer.toString();
  }
}

/// Manages connection to a Flutter app's VM service and provides
/// wrapper methods for custom flutter_copilot.* extensions.
class VmServiceConnector {
  VmServiceConnector() : _logger = logging.Logger('VmServiceConnector');

  final logging.Logger _logger;
  VmService? _service;
  StreamSubscription<Event>? _serviceEventSubscription;
  int _generation = 0;

  /// Called when the remote side closes the socket.
  ///
  /// Not called for [disconnect]. The directory uses this to drop the session.
  void Function()? onDisconnected;

  final Map<String, String?> _registeredServices = {};
  final Map<String, List<Completer<String?>>> _pendingServiceRequests = {};

  /// WebSocket URI of the current DDS connection.
  String? connectedUri;

  /// Returns true if currently connected to a VM service.
  bool get isConnected => _service != null;

  /// Connects to a VM service at the given URI.
  ///
  /// When [waitForExtension] is set, discovery of the Copilot isolate is
  /// retried until the duration elapses. `flutter run` publishes the VM
  /// service before `FlutterCopilotBinding` has registered its extensions.
  ///
  /// Throws an exception if connection fails.
  Future<void> connect(
    String uri, {
    Duration? waitForExtension,
  }) async {
    if (_service != null) {
      _logger.warning('Already connected, disconnecting first');
      await disconnect();
    }

    _logger.info('Connecting to VM service at $uri');
    final generation = _generation;

    try {
      final pending = vmServiceConnectUri(uri);
      final service =
          await pending.timeout(const Duration(seconds: 5), onTimeout: () {
        unawaited(pending.then((lateService) => lateService.dispose(),
            onError: (Object _) {}));
        throw TimeoutException('VM service handshake timed out');
      });
      _service = service;
      connectedUri = uri;
      _serviceEventSubscription = service.onServiceEvent.listen((e) {
        switch (e.kind) {
          case EventKind.kServiceRegistered:
            final serviceName = e.service!;
            _registeredServices[serviceName] = e.method;
            _logger.info('Service registered: $serviceName -> ${e.method}');
            if (_pendingServiceRequests.containsKey(serviceName)) {
              for (final completer in _pendingServiceRequests[serviceName]!) {
                completer.complete(e.method);
              }
              _pendingServiceRequests.remove(serviceName);
            }
          case EventKind.kServiceUnregistered:
            _registeredServices.remove(e.service!);
            _logger.info('Service unregistered: ${e.service}');
          default:
            _logger.info('Service event: $e');
        }
      });
      await service
          .streamListen(EventStreams.kService)
          .timeout(const Duration(seconds: 5));
      unawaited(
        service.onDone.then((_) {
          if (generation != _generation || !identical(_service, service)) {
            return;
          }
          _service = null;
          connectedUri = null;
          _logger.info('VM service connection closed');
          onDisconnected?.call();
        }),
      );

      final isolateId = await _awaitCopilotIsolate(waitForExtension);
      _logger.info('Connected to isolate: $isolateId');
    } catch (err) {
      _generation++;
      final service = _service;
      _service = null;
      connectedUri = null;
      await _serviceEventSubscription?.cancel();
      _serviceEventSubscription = null;
      try {
        await service?.dispose();
      } catch (disposeError) {
        _logger
            .fine('Ignoring dispose error after failed connect: $disposeError');
      }
      _logger.severe('Failed to connect to VM service', err);
      rethrow;
    }
  }

  /// Disconnects from the current VM service.
  Future<void> disconnect() async {
    _generation++;
    final service = _service;
    if (service == null) return;

    _logger.info('Disconnecting from VM service');
    _service = null;
    connectedUri = null;
    await _serviceEventSubscription?.cancel();
    _serviceEventSubscription = null;
    await service.dispose();
    _registeredServices.clear();
    _pendingServiceRequests.clear();
    _logger.fine('Disconnected');
  }

  /// Returns a future that completes with the registered method name for the
  /// given [serviceName].
  ///
  /// If the service is already registered, returns immediately.
  /// Otherwise, waits up to [timeout] for the service to be registered.
  /// Returns `null` if the service is not registered within the timeout.
  Future<String?> waitForServiceRegistration(
    String serviceName, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    if (_registeredServices.containsKey(serviceName)) {
      return _registeredServices[serviceName];
    }

    final completer = Completer<String?>();
    _pendingServiceRequests.putIfAbsent(serviceName, () => []).add(completer);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingServiceRequests[serviceName]?.remove(completer);
        if (_pendingServiceRequests[serviceName]?.isEmpty ?? false) {
          _pendingServiceRequests.remove(serviceName);
        }
        return null;
      },
    );
  }

  /// Best-effort runtime metadata; display names are never used as identity.
  Future<Map<String, dynamic>> describeApp() async {
    _ensureConnected();
    final vm = await _service!.getVM().timeout(const Duration(seconds: 5));
    final isolateId = await _findIsolateWithFlutterCopilotExtensions();
    final isolate = await _service!
        .getIsolate(isolateId)
        .timeout(const Duration(seconds: 5));
    var entry = isolate.rootLib?.uri;
    if (entry?.startsWith('package:') == true) {
      try {
        final resolved = await _service!.lookupResolvedPackageUris(
            isolateId, [entry!]).timeout(const Duration(seconds: 3));
        entry = resolved.uris?.firstOrNull ?? entry;
      } catch (_) {
        // Older VMs and web backends may not support package URI resolution.
      }
    }
    String? root;
    final uri = entry == null ? null : Uri.tryParse(entry);
    if (uri?.scheme == 'file') {
      try {
        final file = File.fromUri(uri!);
        if (file.existsSync()) root = projectDirectory(p.dirname(file.path));
      } catch (_) {
        // Remote source paths are not necessarily accessible on this host.
      }
    }
    return {
      'platform': vm.operatingSystem,
      if (root != null) 'projectRoot': root,
      if (entry != null) 'target': entry,
      'hotReload': _registeredServices.containsKey('reloadSources'),
      'hotRestart': _registeredServices.containsKey('hotRestart'),
    };
  }

  /// Ensures that there is an active connection.
  ///
  /// Throws [NotConnectedException] if not connected.
  void _ensureConnected() {
    if (!isConnected) {
      throw const NotConnectedException();
    }
  }

  /// Calls a VM service extension and handles the response.
  Future<Map<String, dynamic>> _callExtension(
    String extensionName,
    Map<String, dynamic> args,
  ) async {
    _ensureConnected();

    _logger.fine('Calling extension: $extensionName with args: $args');

    try {
      final isolateId = await _findIsolateWithFlutterCopilotExtensions();
      final response = await _service!.callServiceExtension(
        'ext.flutter.$extensionName',
        isolateId: isolateId,
        args: args,
      );

      final responseJson = response.json;
      if (responseJson == null) {
        throw VmServiceExtensionException(
          'Extension $extensionName returned null response',
          null,
          null,
        );
      }

      _logger.finest('Extension response: $responseJson');

      // Check if the response indicates an error
      if (responseJson['status'] == 'Error') {
        throw VmServiceExtensionException(
          'Extension $extensionName failed',
          responseJson['error'] as String?,
          responseJson['stackTrace'] as String?,
        );
      }

      return responseJson;
    } catch (err) {
      _logger.severe('Error calling extension $extensionName', err);
      rethrow;
    }
  }

  /// Gets the list of interactive elements in the widget tree.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getInteractiveElements() {
    return _callExtension('flutter_copilot.interactiveElements', {});
  }

  /// Taps an element matching the given criteria.
  ///
  /// [matcher] should contain one of:
  /// - 'key': matches by `ValueKey<String>`
  /// - 'text': matches by visible text content
  /// - 'type': matches by widget type name
  /// - 'x' and 'y': screen coordinates for tapping at a specific position
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> tap(Map<String, dynamic> matcher) {
    return _callExtension('flutter_copilot.tap', matcher);
  }

  /// Enters text into a text field matching the given criteria.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// [input] is the text to enter.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> enterText(
    Map<String, dynamic> matcher,
    String input,
  ) {
    final args = Map<String, dynamic>.from(matcher)..['input'] = input;
    return _callExtension('flutter_copilot.enterText', args);
  }

  /// Scrolls until an element matching the given criteria is visible.
  ///
  /// [matcher] should contain either 'key' or 'text' field.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> scrollToElement(Map<String, dynamic> matcher) {
    return _callExtension('flutter_copilot.scrollTo', matcher);
  }

  /// Gets the collected application logs.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getLogs() {
    return _callExtension('flutter_copilot.getLogs', {});
  }

  /// Gets the current rebuild snapshot (frame, total rebuilds, top widgets by rebuild count).
  ///
  /// Requires the app to have [enableGlobalRebuildHook] enabled. Returns [enabled]: false
  /// when rebuild tracking is not enabled.
  /// [topLimit] limits how many top-rebuild widgets are returned (default 20).
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> getRebuildSnapshot({int topLimit = 20}) {
    return _callExtension(
      'flutter_copilot.rebuild.snapshot',
      <String, dynamic>{'topLimit': topLimit},
    );
  }

  /// Takes screenshots of all views in the app.
  ///
  /// Returns a list of base64-encoded PNG images.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> takeScreenshots() {
    return _callExtension('flutter_copilot.takeScreenshots', {});
  }

  /// Performs a hot reload of the Flutter app.
  ///
  /// Prefers the `reloadSources` service registered by `flutter run`, which
  /// recompiles and syncs the kernel before reloading. If that service is not
  /// registered within [serviceTimeout], falls back to the VM's built-in
  /// `reloadSources`.
  ///
  /// Throws [NotConnectedException] if not connected.
  Future<bool> hotReload({
    Duration serviceTimeout = const Duration(seconds: 1),
  }) {
    return _invokeFlutterRunService(
      'reloadSources',
      serviceTimeout: serviceTimeout,
      fallbackToVmReload: true,
    );
  }

  /// Performs a hot restart of the Flutter app.
  ///
  /// Calls the `hotRestart` service registered by a debug `flutter run`. There
  /// is no VM fallback: a bare Dart VM cannot hot restart.
  ///
  /// Throws [HotRestartUnavailableException] when the service is not registered
  /// within [serviceTimeout], and [NotConnectedException] if not connected.
  Future<bool> hotRestart({
    Duration serviceTimeout = const Duration(seconds: 1),
  }) {
    return _invokeFlutterRunService(
      'hotRestart',
      serviceTimeout: serviceTimeout,
      fallbackToVmReload: false,
    );
  }

  Future<bool> _invokeFlutterRunService(
    String serviceName, {
    required Duration serviceTimeout,
    required bool fallbackToVmReload,
  }) async {
    _ensureConnected();

    _logger.info('Calling $serviceName');

    try {
      final isolateId = await _findIsolateWithFlutterCopilotExtensions();
      final method = await waitForServiceRegistration(
        serviceName,
        timeout: serviceTimeout,
      );
      if (method == null) {
        if (!fallbackToVmReload) {
          throw const HotRestartUnavailableException();
        }
        final report = await _service!.reloadSources(isolateId);
        _logger.fine('VM reloadSources completed: success=${report.success}');
        return report.success ?? false;
      }

      final result = await _service!.callMethod(method, isolateId: isolateId);
      _logger.fine('$serviceName completed: result=${result.json}');
      return result.json?['type'] == 'Success';
    } catch (err) {
      _logger.severe('$serviceName failed', err);
      rethrow;
    }
  }

  /// Drags an element matching the given criteria.
  ///
  /// [matcher] should contain one of: 'key', 'text', 'type', or 'x'/'y' coordinates.
  /// [params] should contain 'deltaX' and 'deltaY' for relative drag, or 'fromX'/'fromY'/'toX'/'toY' for absolute drag.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> drag(
    Map<String, dynamic> matcher,
    Map<String, dynamic> params,
  ) {
    final args = Map<String, dynamic>.from(matcher)..addAll(params);
    return _callExtension('flutter_copilot.drag', args);
  }

  /// Swipes an element matching the given criteria in the specified direction.
  ///
  /// [matcher] should contain one of: 'key', 'text', 'type', or 'x'/'y' coordinates.
  /// [direction] should be one of: 'left', 'right', 'up', 'down'.
  /// [distance] is the swipe distance in pixels (optional, default: 200).
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> swipe(
    Map<String, dynamic> matcher,
    String direction,
    double? distance,
  ) {
    final args = Map<String, dynamic>.from(matcher)..['direction'] = direction;
    if (distance != null) {
      args['distance'] = distance;
    }
    return _callExtension('flutter_copilot.swipe', args);
  }

  /// Long presses an element matching the given criteria.
  ///
  /// [matcher] should contain one of: 'key', 'text', 'type', or 'x'/'y' coordinates.
  /// [duration] is the press duration in milliseconds (optional, default: 500).
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> longPress(
    Map<String, dynamic> matcher,
    int? duration,
  ) {
    final args = Map<String, dynamic>.from(matcher);
    if (duration != null) {
      args['duration'] = duration;
    }
    return _callExtension('flutter_copilot.longPress', args);
  }

  /// Double taps an element matching the given criteria.
  ///
  /// [matcher] should contain one of: 'key', 'text', 'type', or 'x'/'y' coordinates.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> doubleTap(Map<String, dynamic> matcher) {
    return _callExtension('flutter_copilot.doubleTap', matcher);
  }

  /// Controls app navigation.
  ///
  /// [action] should be one of: 'push', 'pop', 'replace', 'pushReplacement', 'popUntil'.
  /// [route] is the route name (required for push/replace actions).
  /// [arguments] are optional route arguments.
  /// Throws [NotConnectedException] if not connected.
  Future<Map<String, dynamic>> navigate(
    String action,
    String? route,
    Map<String, dynamic>? arguments,
  ) {
    final args = <String, dynamic>{'action': action};
    if (route != null) {
      args['route'] = route;
    }
    if (arguments != null) {
      args['arguments'] = arguments;
    }
    return _callExtension('flutter_copilot.navigate', args);
  }

  Future<String> _awaitCopilotIsolate(Duration? timeout) async {
    if (timeout == null || timeout <= Duration.zero) {
      return _findIsolateWithFlutterCopilotExtensions();
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        return await _findIsolateWithFlutterCopilotExtensions();
      } on NoCopilotExtensionException {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Finds the first isolate that has the flutter_copilot extensions.
  ///
  /// Throws an exception if no suitable isolate is found.
  Future<String> _findIsolateWithFlutterCopilotExtensions() async {
    final vm = await _service!.getVM();
    if (vm.isolates == null || vm.isolates!.isEmpty) {
      throw Exception('No isolates found in the VM');
    }

    // Find the first isolate that has the flutter_copilot.getLogs extension
    for (final isolateRef in vm.isolates!) {
      if (isolateRef.id == null) {
        continue;
      }

      try {
        final isolate = await _service!.getIsolate(isolateRef.id!);
        final hasExtension = isolate.extensionRPCs?.any(
              (ext) => ext == 'ext.flutter.flutter_copilot.getLogs',
            ) ??
            false;

        if (hasExtension) {
          return isolateRef.id!;
        }
      } catch (err) {
        _logger.warning(
          'Failed to check extensions for isolate ${isolateRef.id}',
          err,
        );
        continue;
      }
    }

    throw NoCopilotExtensionException(connectedUri);
  }
}
