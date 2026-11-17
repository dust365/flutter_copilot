/// Converts a VM service address into the WebSocket URI DDS expects.
///
/// `flutter run` prints `http://127.0.0.1:PORT/TOKEN=/`. The VM service client
/// accepts `ws://127.0.0.1:PORT/TOKEN=/ws`.
String normalizeVmServiceUri(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  if (text.isEmpty) {
    throw FormatException('VM service URI is empty');
  }

  final uri = Uri.parse(text);
  final scheme = switch (uri.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    'ws' || 'wss' => uri.scheme,
    _ => throw FormatException(
        "Unsupported VM service URI scheme '${uri.scheme}'. "
        'Use ws:// or the http:// address printed by flutter run.',
      ),
  };

  var path = uri.path;
  if (path.isEmpty) {
    path = '/ws';
  } else if (path.endsWith('/ws')) {
    // Already a websocket path.
  } else if (path.endsWith('/')) {
    path = '${path}ws';
  } else {
    path = '$path/ws';
  }

  return uri.replace(scheme: scheme, path: path).removeFragment().toString();
}

/// Canonical form of a DTD websocket address. Unlike a VM service URI, a DTD
/// path must be left unchanged.
String canonicalDtdUri(String raw) {
  final text = raw.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');
  if (text.isEmpty) {
    throw FormatException('DTD URI is empty');
  }
  final uri = Uri.parse(text);
  if (uri.scheme != 'ws' && uri.scheme != 'wss') {
    throw FormatException(
      'DTD URI must be ws:// or wss://. Got ${uri.scheme}://. '
      'A VM service address belongs to the connect tool.',
    );
  }
  const localHosts = {'localhost', '127.0.0.1', '::1'};
  if (!localHosts.contains(uri.host)) {
    throw FormatException(
      'DTD URI must be on this machine ($text).',
    );
  }
  return uri.removeFragment().toString();
}
