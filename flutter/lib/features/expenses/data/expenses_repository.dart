import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/expense_record.dart';

final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return ExpensesRepository(ref.watch(dioProvider));
});

class ExpensesRepository {
  ExpensesRepository(this._dio);

  final Dio _dio;

  Future<List<ExpenseRecord>> fetchExpenses(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/expenses',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['expenses'] as List?) ?? const [];
    return raw
        .map((item) => ExpenseRecord.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> createExpense({
    required String token,
    required double amount,
    required String reason,
    required String spentAt,
  }) async {
    await _dio.post<void>(
      '/expenses',
      data: {
        'amount': amount,
        'reason': reason.trim(),
        'spentAt': spentAt,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateExpense({
    required String token,
    required String id,
    required double amount,
    required String reason,
    required String spentAt,
  }) async {
    await _dio.put<void>(
      '/expenses/$id',
      data: {
        'amount': amount,
        'reason': reason.trim(),
        'spentAt': spentAt,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteExpense({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/expenses/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}
