import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/app_settings_record.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(dioProvider));
});

class SettingsRepository {
  SettingsRepository(this._dio);

  final Dio _dio;

  Future<AppSettingsRecord> fetchSettings(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/settings',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final raw = response.data?['settings'];
    final data = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return AppSettingsRecord.fromJson(data);
  }

  Future<AppSettingsRecord> updateSettings({
    required String token,
    required AppSettingsRecord settings,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/settings',
      data: settings.toJson(),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final raw = response.data?['settings'];
    final data = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
    return AppSettingsRecord.fromJson(data);
  }

  Future<Map<String, dynamic>> openCashDrawer({
    required String token,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/settings/cash-drawer/open',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data ?? const <String, dynamic>{};
  }
}
