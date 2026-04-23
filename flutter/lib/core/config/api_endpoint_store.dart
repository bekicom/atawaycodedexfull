import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

class ApiEndpointStore {
  static const _apiBaseUrlKey = 'api_base_url';

  static String normalize(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return AppConfig.apiBaseUrl;
    }
    if (!trimmed.contains('://')) {
      trimmed = 'http://$trimmed';
    }
    trimmed = trimmed.replaceAll(RegExp(r'/+$'), '');
    return trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
  }

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_apiBaseUrlKey);
    final normalized = normalize(saved ?? AppConfig.apiBaseUrl);
    if (saved != normalized) {
      await prefs.setString(_apiBaseUrlKey, normalized);
    }
    return normalized;
  }

  static Future<void> saveBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiBaseUrlKey, normalize(value));
  }
}
