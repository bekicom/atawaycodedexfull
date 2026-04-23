import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../data/categories_repository.dart';
import '../domain/category_record.dart';

final categoriesProvider = FutureProvider<List<CategoryRecord>>((ref) async {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    throw Exception('Session topilmadi');
  }

  return ref.watch(categoriesRepositoryProvider).fetchCategories(session.token);
});

final categoriesActionControllerProvider =
    AsyncNotifierProvider<CategoriesActionController, void>(
      CategoriesActionController.new,
    );

class CategoriesActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> saveCategory({String? id, required String name}) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(categoriesRepositoryProvider);
      if (id == null || id.isEmpty) {
        await repo.createCategory(token: session.token, name: name);
      } else {
        await repo.updateCategory(token: session.token, id: id, name: name);
      }

      ref.invalidate(categoriesProvider);
      ref.invalidate(dashboardOverviewProvider);
    });
  }

  Future<void> removeCategory(String id) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(categoriesRepositoryProvider)
          .deleteCategory(token: session.token, id: id);
      ref.invalidate(categoriesProvider);
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
