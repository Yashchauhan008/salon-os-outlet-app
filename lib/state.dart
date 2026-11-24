import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Backend address baked in at build time: --dart-define=API_URL=https://host/api/v1
const String kDefaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://api.salon.yashchauhan.pro/api/v1');

late AppState appState;

class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  late final ApiClient api;

  ThemeMode themeMode = ThemeMode.system;
  Map<String, dynamic>? me;
  bool booting = true;
  String? sessionMessage;

  AppState(this.prefs) {
    final saved = prefs.getString('theme');
    if (saved == 'light') themeMode = ThemeMode.light;
    if (saved == 'dark') themeMode = ThemeMode.dark;
    api = ApiClient(baseUrl: prefs.getString('server_url') ?? kDefaultApiUrl);
    api.refreshToken = prefs.getString('refresh_token');
    api.onTokensChanged = (access, refresh) {
      if (refresh == null) {
        prefs.remove('refresh_token');
      } else {
        prefs.setString('refresh_token', refresh);
      }
    };
    api.onSessionExpired = () {
      me = null;
      sessionMessage = 'Your session expired. Please sign in again.';
      notifyListeners();
    };
  }

  String get serverUrl => api.baseUrl;

  void setServerUrl(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    api.baseUrl = u;
    prefs.setString('server_url', u);
  }

  Future<void> init() async {
    if (api.refreshToken != null) {
      try {
        await _loadMe();
      } catch (_) {
        me = null;
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> _loadMe() async {
    final data = await api.get('/auth/me');
    me = data as Map<String, dynamic>;
  }

  Future<void> login(String email, String password) async {
    sessionMessage = null;
    final data = await api.post('/auth/login', body: {'email': email.trim(), 'password': password}) as Map<String, dynamic>;
    api.accessToken = data['access_token'] as String?;
    api.refreshToken = data['refresh_token'] as String?;
    api.onTokensChanged?.call(api.accessToken, api.refreshToken);
    await _loadMe();
    if (me!['scope'] != 'outlet') {
      // This app is for outlet users. Organization owners use the Admin Web.
      await logout(callServer: true);
      throw ApiException(403, 'This app is for outlet staff. Organization admins should use the Admin Web.');
    }
    notifyListeners();
  }

  Future<void> logout({bool callServer = true}) async {
    if (callServer && api.accessToken != null) {
      try {
        await api.post('/auth/logout');
      } catch (_) {}
    }
    api.accessToken = null;
    api.refreshToken = null;
    api.onTokensChanged?.call(null, null);
    me = null;
    notifyListeners();
  }

  bool can(String permission) {
    final list = me?['permissions'];
    if (list is List) return list.contains(permission);
    return false;
  }

  String? get outletId {
    final o = me?['outlet'];
    if (o is Map) return o['id'] as String?;
    return null;
  }

  String get outletName {
    final o = me?['outlet'];
    if (o is Map) return (o['name'] as String?) ?? '';
    return '';
  }

  String get userName {
    final u = me?['user'];
    if (u is Map) return (u['name'] as String?) ?? '';
    return '';
  }

  String get roleLabel => ((me?['role'] as String?) ?? '').replaceAll('_', ' ');

  void cycleTheme() {
    themeMode = themeMode == ThemeMode.system
        ? ThemeMode.light
        : themeMode == ThemeMode.light
            ? ThemeMode.dark
            : ThemeMode.system;
    prefs.setString('theme', themeMode == ThemeMode.light ? 'light' : themeMode == ThemeMode.dark ? 'dark' : 'system');
    notifyListeners();
  }
}
