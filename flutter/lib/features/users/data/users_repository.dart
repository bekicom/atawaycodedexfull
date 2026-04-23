import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/app_user_record.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.watch(dioProvider));
});

class UsersRepository {
  UsersRepository(this._dio);

  final Dio _dio;

  Future<List<AppUserRecord>> fetchUsers(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/users',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final rawUsers = (response.data?['users'] as List?) ?? const [];
    return rawUsers
        .map(
          (item) =>
              AppUserRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> createUser({
    required String token,
    required String username,
    required String password,
    required String role,
  }) async {
    await _dio.post<void>(
      '/admin/users',
      data: {'username': username.trim(), 'password': password, 'role': role},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateUser({
    required String token,
    required String id,
    required String username,
    required String password,
    required String role,
  }) async {
    await _dio.put<void>(
      '/admin/users/$id',
      data: {'username': username.trim(), 'password': password, 'role': role},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteUser({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/admin/users/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}
