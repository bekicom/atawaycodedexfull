import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/category_record.dart';

final categoriesRepositoryProvider = Provider<CategoriesRepository>((ref) {
  return CategoriesRepository(ref.watch(dioProvider));
});

class CategoriesRepository {
  CategoriesRepository(this._dio);

  final Dio _dio;

  Future<List<CategoryRecord>> fetchCategories(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/categories',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final raw = (response.data?['categories'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              CategoryRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> createCategory({
    required String token,
    required String name,
  }) async {
    await _dio.post<void>(
      '/categories',
      data: {'name': name.trim()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateCategory({
    required String token,
    required String id,
    required String name,
  }) async {
    await _dio.put<void>(
      '/categories/$id',
      data: {'name': name.trim()},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteCategory({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/categories/$id',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
  }
}
