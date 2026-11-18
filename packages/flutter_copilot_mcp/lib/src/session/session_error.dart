/// Machine-readable failures shared by MCP and fcc.
class SessionError implements Exception {
  SessionError(this.code, this.message, {this.candidates = const []});

  final String code;
  final String message;
  final List<Map<String, dynamic>> candidates;

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (candidates.isNotEmpty) 'candidates': candidates,
      };

  @override
  String toString() => message;
}
