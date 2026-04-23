import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/sales_history_record.dart';
import '../domain/variant_sales_insights_record.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  return SalesRepository(ref.watch(dioProvider));
});

class SalesRepository {
  SalesRepository(this._dio);

  final Dio _dio;

  Future<SalesHistoryRecord> fetchSales({
    required String token,
    required String period,
    required String from,
    required String to,
    String cashierUsername = '',
    String shiftId = '',
  }) async {
    final query = <String, dynamic>{'limit': 300};
    if (period.isNotEmpty && period != 'all') {
      query['period'] = period;
    }
    if (from.isNotEmpty) query['from'] = from;
    if (to.isNotEmpty) query['to'] = to;
    if (cashierUsername.trim().isNotEmpty) {
      query['cashierUsername'] = cashierUsername.trim();
    }
    if (shiftId.trim().isNotEmpty) {
      query['shiftId'] = shiftId.trim();
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/sales',
      queryParameters: query,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return SalesHistoryRecord.fromJson(response.data ?? const {});
  }

  Future<Map<String, dynamic>> createSale({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/sales',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> returnSale({
    required String token,
    required String saleId,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/sales/$saleId/returns',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data ?? const <String, dynamic>{};
  }

  Future<VariantSalesInsightsRecord> fetchVariantInsights({
    required String token,
    required String period,
    required String from,
    required String to,
    String cashierUsername = '',
    String shiftId = '',
    String size = '',
    String color = '',
  }) async {
    final query = <String, dynamic>{};
    if (period.isNotEmpty && period != 'all') {
      query['period'] = period;
    }
    if (from.isNotEmpty) query['from'] = from;
    if (to.isNotEmpty) query['to'] = to;
    if (cashierUsername.trim().isNotEmpty) {
      query['cashierUsername'] = cashierUsername.trim();
    }
    if (shiftId.trim().isNotEmpty) {
      query['shiftId'] = shiftId.trim();
    }
    if (size.trim().isNotEmpty) {
      query['size'] = size.trim();
    }
    if (color.trim().isNotEmpty) {
      query['color'] = color.trim();
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/sales/variant-insights',
      queryParameters: query,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return VariantSalesInsightsRecord.fromJson(response.data ?? const {});
  }
}
