import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/dashboard_overview.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(dioProvider));
});

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  Future<DashboardOverview> fetchOverview(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/overview',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return DashboardOverview.fromJson(response.data ?? const {});
  }
}
