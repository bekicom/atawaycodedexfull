import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/returns_record.dart';

final returnsRepositoryProvider = Provider<ReturnsRepository>((ref) {
  return ReturnsRepository(ref.watch(dioProvider));
});

class ReturnsRepository {
  ReturnsRepository(this._dio);

  final Dio _dio;

  Future<ReturnsRecord> fetchReturns({
    required String token,
    required String period,
    required String from,
    required String to,
  }) async {
    final query = <String, dynamic>{'limit': 300};
    if (period.isNotEmpty && period != 'all') query['period'] = period;
    if (from.isNotEmpty) query['from'] = from;
    if (to.isNotEmpty) query['to'] = to;

    final response = await _dio.get<Map<String, dynamic>>(
      '/sales/returns',
      queryParameters: query,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return ReturnsRecord.fromJson(response.data ?? const {});
  }
}
