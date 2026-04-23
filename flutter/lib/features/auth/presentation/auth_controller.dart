import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider));
});

final authControllerProvider = AsyncNotifierProvider<AuthController, Session?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    return ref.read(authRepositoryProvider).restoreSession();
  }

  Future<void> signIn({
    required String username,
    required String password,
    String tenantSlug = '',
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref
          .read(authRepositoryProvider)
          .login(
            username: username,
            password: password,
            tenantSlug: tenantSlug,
          );
    });
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
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
    final text = error.toString().trim();
    if (text.isNotEmpty &&
        text != 'Exception' &&
        text != 'null' &&
        text != 'Xatolik yuz berdi') {
      return text;
    }
    return 'Xatolik yuz berdi';
  }
}
