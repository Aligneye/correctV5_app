import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:correctv1/splash_screen.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:correctv1/services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.none);
  await ThemeService.instance.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const supabaseUrl = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://ulphnmkitdedjpvcmhkm.supabase.co',
    );
    const supabaseAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'sb_publishable_qwmO0yArdX1mls7P-yaRxA_2yEBfA0Z',
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'align',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.noScaling),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashScreen(
            supabaseUrl: supabaseUrl,
            supabaseAnonKey: supabaseAnonKey,
          ),
        );
      },
    );
  }
}
