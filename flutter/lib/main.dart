import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/api_endpoint_store.dart';
import 'core/network/api_client.dart';
import 'features/customer_display/presentation/customer_display_shell.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final apiBaseUrl = await ApiEndpointStore.loadBaseUrl();
  final isCustomerDisplay = args.contains('--customer-display');
  String? cashierArg;
  for (final arg in args) {
    if (arg.startsWith('--cashier=')) {
      cashierArg = arg;
      break;
    }
  }
  final initialCashier = cashierArg == null
      ? ''
      : cashierArg.replaceFirst('--cashier=', '').trim();

  if (isCustomerDisplay) {
    runApp(
      CustomerDisplayShell(
        initialApiBaseUrl: apiBaseUrl,
        initialCashierUsername: initialCashier,
      ),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        apiBaseUrlProvider.overrideWith((ref) => apiBaseUrl),
      ],
      child: const UyDokonApp(),
    ),
  );
}
