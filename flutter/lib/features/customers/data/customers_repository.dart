import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/customer_record.dart';

final customersRepositoryProvider = Provider<CustomersRepository>((ref) {
  return CustomersRepository(ref.watch(dioProvider));
});

class CustomersRepository {
  CustomersRepository(this._dio);

  final Dio _dio;

  Future<CustomersListRecord> fetchCustomers(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/customers',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return CustomersListRecord.fromJson(response.data ?? const {});
  }

  Future<List<CustomerRecord>> lookupCustomers({
    required String token,
    String query = '',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/customers/lookup',
      queryParameters: query.trim().isEmpty ? null : {'q': query.trim()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final rawCustomers = (response.data?['customers'] as List?) ?? const [];
    return rawCustomers
        .map(
          (item) =>
              CustomerRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> createCustomer({
    required String token,
    required String fullName,
    required String phone,
    required String address,
    required double openingBalanceAmount,
    required String openingBalanceCurrency,
  }) async {
    await _dio.post<void>(
      '/customers',
      data: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'openingBalanceAmount': openingBalanceAmount,
        'openingBalanceCurrency': openingBalanceCurrency,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateCustomer({
    required String token,
    required String id,
    required String fullName,
    required String phone,
    required String address,
    required double openingBalanceAmount,
    required String openingBalanceCurrency,
  }) async {
    await _dio.put<void>(
      '/customers/$id',
      data: {
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'openingBalanceAmount': openingBalanceAmount,
        'openingBalanceCurrency': openingBalanceCurrency,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<CustomerLedgerRecord> fetchLedger({
    required String token,
    required String id,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/customers/$id/ledger',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return CustomerLedgerRecord.fromJson(response.data ?? const {});
  }

  Future<void> payDebt({
    required String token,
    required String id,
    required double amount,
    required String note,
  }) async {
    await _dio.post<void>(
      '/customers/$id/payments',
      data: {'amount': amount, 'note': note.trim()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteCustomer({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/customers/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}
