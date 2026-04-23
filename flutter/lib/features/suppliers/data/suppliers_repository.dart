import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/supplier_record.dart';

final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  return SuppliersRepository(ref.watch(dioProvider));
});

class SuppliersRepository {
  SuppliersRepository(this._dio);

  final Dio _dio;

  Future<List<SupplierRecord>> fetchSuppliers(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/suppliers',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final raw = (response.data?['suppliers'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              SupplierRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> createSupplier({
    required String token,
    required String name,
    required String address,
    required String phone,
    required double openingBalanceAmount,
    required String openingBalanceCurrency,
  }) async {
    await _dio.post<void>(
      '/suppliers',
      data: {
        'name': name.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'openingBalanceAmount': openingBalanceAmount,
        'openingBalanceCurrency': openingBalanceCurrency,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateSupplier({
    required String token,
    required String id,
    required String name,
    required String address,
    required String phone,
    required double openingBalanceAmount,
    required String openingBalanceCurrency,
  }) async {
    await _dio.put<void>(
      '/suppliers/$id',
      data: {
        'name': name.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'openingBalanceAmount': openingBalanceAmount,
        'openingBalanceCurrency': openingBalanceCurrency,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteSupplier({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/suppliers/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<SupplierLedgerRecord> fetchLedger({
    required String token,
    required String id,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/suppliers/$id/purchases',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return SupplierLedgerRecord.fromJson(response.data ?? const {});
  }

  Future<void> payDebt({
    required String token,
    required String id,
    required double amount,
    required String note,
  }) async {
    await _dio.post<void>(
      '/suppliers/$id/payments',
      data: {'amount': amount, 'note': note.trim()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}
