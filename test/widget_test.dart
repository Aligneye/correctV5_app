import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:correctv1/splash_screen.dart';
import 'package:correctv1/theme/app_theme.dart';

void main() {
  testWidgets('splash screen renders logo and tagline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const SplashScreen(
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
      ),
    );

    // Let the scale animation start
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('REDEFINING POSTURE'), findsOneWidget);
  });
}
