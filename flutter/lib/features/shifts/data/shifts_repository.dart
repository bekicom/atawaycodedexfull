import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/shift_record.dart';

final shiftsRepositoryProvider = Provider<ShiftsRepository>((ref) {
  return ShiftsRepository(ref.watch(dioProvider));
});

class ShiftsRepository {
  ShiftsRepository(this._dio);

  final Dio _dio;

  Future<ShiftRecord?> fetchCurrentShift(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/shifts/current',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final rawShift = response.data?['shift'];
    if (rawShift is Map<String, dynamic>) {
      return ShiftRecord.fromJson(rawShift);
    }
    if (rawShift is Map) {
      return ShiftRecord.fromJson(Map<String, dynamic>.from(rawShift));
    }
    return null;
  }

  Future<ShiftRecord> openShift(String token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/shifts/open',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final rawShift = response.data?['shift'];
    return ShiftRecord.fromJson(
      rawShift is Map<String, dynamic>
          ? rawShift
          : Map<String, dynamic>.from(rawShift as Map),
    );
  }

  Future<ShiftRecord> closeCurrentShift(String token) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/shifts/current/close',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final rawShift = response.data?['shift'];
    return ShiftRecord.fromJson(
      rawShift is Map<String, dynamic>
          ? rawShift
          : Map<String, dynamic>.from(rawShift as Map),
    );
  }

  Future<ShiftsListRecord> fetchShifts({
    required String token,
    required String period,
    required String from,
    required String to,
    String cashierUsername = '',
    String status = '',
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
    if (status.trim().isNotEmpty) {
      query['status'] = status.trim();
    }

    final response = await _dio.get<Map<String, dynamic>>(
      '/shifts',
      queryParameters: query,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return ShiftsListRecord.fromJson(response.data ?? const {});
  }
}
