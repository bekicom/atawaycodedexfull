import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kiyim_dokon_pos/app/app.dart';

void main() {
  testWidgets('login page renders', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: UyDokonApp()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final hasLoginTitle = find.text('Kirish').evaluate().isNotEmpty;
    final hasLoader =
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    expect(hasLoginTitle || hasLoader, isTrue);
  });
}
