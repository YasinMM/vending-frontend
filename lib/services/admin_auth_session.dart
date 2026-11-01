import 'dart:convert';

class AdminAuthSession {
  AdminAuthSession._();

  static String? _username;
  static String? _password;

  static bool get isAuthenticated => _username != null && _password != null;

  static String? get authorizationHeader {
    final username = _username;
    final password = _password;
    if (username == null || password == null) return null;
    return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
  }

  static void setCredentials(String username, String password) {
    _username = username;
    _password = password;
  }

  static void clear() {
    _username = null;
    _password = null;
  }
}
