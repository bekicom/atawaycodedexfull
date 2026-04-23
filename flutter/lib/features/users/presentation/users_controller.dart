import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../data/users_repository.dart';
import '../domain/app_user_record.dart';

final usersProvider = FutureProvider<List<AppUserRecord>>((ref) async {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    throw Exception('Session topilmadi');
  }

  return ref.watch(usersRepositoryProvider).fetchUsers(session.token);
});

final usersActionControllerProvider =
    AsyncNotifierProvider<UsersActionController, void>(
      UsersActionController.new,
    );

class UsersActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveUser({
    String? id,
    required String username,
    required String password,
    required String role,
  }) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(usersRepositoryProvider);
      if (id == null || id.isEmpty) {
        await repo.createUser(
          token: session.token,
          username: username,
          password: password,
          role: role,
        );
      } else {
        await repo.updateUser(
          token: session.token,
          id: id,
          username: username,
          password: password,
          role: role,
        );
      }

      ref.invalidate(usersProvider);
      ref.invalidate(dashboardOverviewProvider);
    });
  }

  Future<void> deleteUser({required String id}) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(usersRepositoryProvider)
          .deleteUser(token: session.token, id: id);

      ref.invalidate(usersProvider);
      ref.invalidate(dashboardOverviewProvider);
    });
  }

  String formatError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return 'Xatolik yuz berdi';
  }
}
