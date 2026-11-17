import 'dart:convert';

import 'package:flutter_copilot_mcp/src/session/vm_service_uri.dart';

/// Addresses discovered from one `flutter run --machine` line.
class MachineLine {
  const MachineLine({this.wsUri, this.dtdUri});

  final String? wsUri;
  final String? dtdUri;

  bool get isEmpty => wsUri == null && dtdUri == null;
}

/// Reads `app.debugPort` and `app.dtd` events from a `--machine` line.
///
/// Returns null when the line is not one of those events. A line may be a
/// JSON object or a one-element JSON array, which is what `flutter run
/// --machine` prints.
MachineLine? parseMachineLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;

  String? wsUri;
  String? dtdUri;

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    final decoded = _tryDecode(trimmed);
    if (decoded != null) {
      final events = decoded is List ? decoded : <dynamic>[decoded];
      for (final event in events) {
        if (event is! Map) continue;
        final name = event['event']?.toString();
        final params = event['params'];
        final map = params is Map
            ? params.map((key, value) => MapEntry(key.toString(), value))
            : const <String, dynamic>{};
        if (name == 'app.debugPort') {
          wsUri = _debugPortUri(map) ?? wsUri;
        } else if (name == 'app.dtd') {
          final uri = map['uri'] ?? map['dtdUri'];
          if (uri != null && uri.toString().isNotEmpty) {
            dtdUri = uri.toString();
          }
        }
      }
    }
  }

  wsUri ??= _httpServiceUri(trimmed);
  if (wsUri == null && dtdUri == null) return null;
  return MachineLine(wsUri: wsUri, dtdUri: dtdUri);
}

/// A device entry from `flutter devices --machine`.
class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.supported,
    required this.targetPlatform,
    required this.emulator,
  });

  final String id;
  final String name;
  final bool supported;
  final String targetPlatform;
  final bool emulator;

  String describe() {
    final where = emulator ? 'emulator' : 'device';
    final state = supported ? where : '$where, unsupported';
    return '$id  $name  $targetPlatform  ($state)';
  }
}

/// Parses `flutter devices --machine` output.
///
/// Flutter may print log lines around the JSON array. The array is taken from
/// the first `[` through the matching end of the string's last `]`.
List<FlutterDevice> parseFlutterDevices(String output) {
  final start = output.indexOf('[');
  final end = output.lastIndexOf(']');
  if (start < 0 || end < start) return const [];

  final decoded = jsonDecode(output.substring(start, end + 1));
  if (decoded is! List) return const [];

  final devices = <FlutterDevice>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    devices.add(
      FlutterDevice(
        id: id,
        name: item['name']?.toString() ?? id,
        supported: item['isSupported'] != false,
        targetPlatform: item['targetPlatform']?.toString() ?? '',
        emulator: item['emulator'] == true,
      ),
    );
  }
  return devices;
}

String formatFlutterDevices(List<FlutterDevice> devices) {
  if (devices.isEmpty) return 'No devices reported by flutter devices.';
  return devices.map((device) => '- ${device.describe()}').join('\n');
}

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

String? _debugPortUri(Map<String, dynamic> params) {
  final wsUri = params['wsUri']?.toString();
  if (wsUri != null && wsUri.isNotEmpty) {
    return normalizeVmServiceUri(wsUri);
  }
  final baseUri = params['baseUri']?.toString();
  if (baseUri != null && baseUri.isNotEmpty) {
    return normalizeVmServiceUri(baseUri);
  }
  return null;
}

final _httpService = RegExp(r'https?://127\.0\.0\.1:\d+/[A-Za-z0-9_=\-]+/');

String? _httpServiceUri(String line) {
  final match = _httpService.firstMatch(line);
  if (match == null) return null;
  return normalizeVmServiceUri(match.group(0)!);
}
