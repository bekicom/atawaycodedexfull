import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/cashier/presentation/cashier_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';

class AuthRouterNotifier extends ChangeNotifier {
  AuthRouterNotifier(Ref ref) {
    ref.listen<AsyncValue<dynamic>>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = AuthRouterNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/cashier',
        builder: (context, state) => const CashierPage(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardPage(),
      ),
    ],
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider);
      if (authState.isLoading) return null;

      final session = authState.valueOrNull;
      final isLoggedIn = session != null;
      final isLoginRoute = state.matchedLocation == '/login';
      final isCashierRoute = state.matchedLocation == '/cashier';
      final isDashboardRoute = state.matchedLocation == '/dashboard';
      final role = session?.user.role.trim().toLowerCase() ?? '';
      final isCashier = role == 'cashier' || role == 'kassa';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (!isLoggedIn) return null;

      if (isCashier) {
        if (!isCashierRoute) return '/cashier';
        return null;
      }

      if (isLoginRoute || (!isDashboardRoute && !isCashierRoute)) {
        return '/dashboard';
      }
      return null;
    },
  );
});
