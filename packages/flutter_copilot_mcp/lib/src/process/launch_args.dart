/// Arguments a caller may append to `flutter run`.
///
/// Everything else is rejected so a prompt cannot redirect the build with
/// flags such as `--dart-define-from-file` or `--use-application-binary`.
const allowedLaunchFlags = <String>{
  '--debug',
  '--profile',
  '--flavor',
  '--dart-define',
};

const _flagsWithValue = <String>{
  '--flavor',
  '--dart-define',
};

class LaunchArgsException implements Exception {
  LaunchArgsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Throws [LaunchArgsException] when [args] contains a flag this server does
/// not pass through.
void validateLaunchArgs(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.trim().isEmpty) {
      throw LaunchArgsException('Empty launch argument');
    }
    final flag = arg.split('=').first;
    if (!_isAllowed(flag)) {
      throw LaunchArgsException(
        'Launch argument not allowed: $arg. '
        'Allowed flags: ${allowedLaunchFlags.join(', ')}.',
      );
    }
    final takesValue = _flagsWithValue.contains(flag) && !arg.contains('=');
    if (takesValue) {
      if (i + 1 >= args.length || args[i + 1].startsWith('-')) {
        throw LaunchArgsException('Missing value for $flag');
      }
      i++;
    } else if (_flagsWithValue.contains(flag) && arg.endsWith('=')) {
      throw LaunchArgsException('Missing value for $flag');
    }
  }
}

bool _isAllowed(String flag) => allowedLaunchFlags.contains(flag);
