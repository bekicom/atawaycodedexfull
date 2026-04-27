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
    final query = <String, dynamic>{'limit': 5000};
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

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/sales',
        queryParameters: query,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return SalesHistoryRecord.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      final fallback = await _fetchSalesWithFallbackBaseUrls(
        token: token,
        query: query,
      );
      if (fallback != null) return fallback;
      rethrow;
    }
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

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/sales/variant-insights',
        queryParameters: query,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return VariantSalesInsightsRecord.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return VariantSalesInsightsRecord.empty();
      }
      rethrow;
    }
  }

  Future<SalesHistoryRecord?> _fetchSalesWithFallbackBaseUrls({
    required String token,
    required Map<String, dynamic> query,
  }) async {
    final currentBaseUrl = _dio.options.baseUrl.trim();
    final candidates = _buildFallbackBaseUrls(currentBaseUrl);
    if (candidates.isEmpty) return null;

    for (final candidate in candidates) {
      try {
        final fallbackDio = Dio(_dio.options.copyWith(baseUrl: candidate));
        final response = await fallbackDio.get<Map<String, dynamic>>(
          '/sales',
          queryParameters: query,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return SalesHistoryRecord.fromJson(response.data ?? const {});
      } on DioException catch (error) {
        if (error.response?.statusCode == 404) {
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  List<String> _buildFallbackBaseUrls(String currentBaseUrl) {
    final result = <String>[];
    final current = currentBaseUrl.replaceAll(RegExp(r'/+$'), '');
    if (current.isEmpty) return result;

    void add(String value) {
      final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isEmpty) return;
      if (normalized == current) return;
      if (!result.contains(normalized)) {
        result.add(normalized);
      }
    }

    if (current.endsWith('/api')) {
      add(current.substring(0, current.length - 4));
    } else {
      add('$current/api');
    }

    final uri = Uri.tryParse(current);
    if (uri != null && uri.hasAuthority) {
      final host = uri.host;
      final scheme = uri.scheme.isEmpty ? 'http' : uri.scheme;
      final currentPort = uri.hasPort ? uri.port : null;

      if (currentPort != 4000) {
        final portBase = '$scheme://$host:4000';
        add('$portBase/api');
        add(portBase);
      }
    }

    return result;
  }
}
