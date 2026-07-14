import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:correctv1/auth/auth_gate.dart';
import 'package:correctv1/home/home_page.dart';
import 'package:correctv1/services/session_database.dart';
import 'package:correctv1/services/session_sync_service.dart';
import 'package:correctv1/services/background_service.dart';
import 'package:correctv1/services/notification_service.dart';
import 'package:correctv1/legal/disclaimer_prefs.dart';
import 'package:correctv1/legal/disclaimer_gate_page.dart';

class SplashScreen extends StatefulWidget {
  final String supabaseUrl;
  final String supabaseAnonKey;

  const SplashScreen({
    super.key,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -12.0, end: 12.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.wait([
        _initApp(),
        Future.delayed(const Duration(milliseconds: 2500)),
      ]).then((_) => _navigate());
    });
  }

  Future<void> _initApp() async {
    final isConfigured =
        widget.supabaseUrl.isNotEmpty && widget.supabaseAnonKey.isNotEmpty;
    if (isConfigured) {
      await Supabase.initialize(
        url: widget.supabaseUrl,
        anonKey: widget.supabaseAnonKey,
      );
    }
    await SessionDatabase.instance.initialize();
    SessionSyncService.instance.start();
    await initBackgroundService();
    await NotificationService.instance.initialize();
  }

  void _navigate() {
    if (!mounted) return;
    final isConfigured =
        widget.supabaseUrl.isNotEmpty && widget.supabaseAnonKey.isNotEmpty;
    final destination = isConfigured ? const AuthGate() : const HomePage();
    _navigateWithDisclaimerCheck(destination);
  }

  Future<void> _navigateWithDisclaimerCheck(Widget destination) async {
    final accepted = await DisclaimerPrefs.hasAcceptedCurrentVersion();
    if (!mounted) return;
    final target = accepted
        ? destination
        : DisclaimerGatePage(nextScreen: destination);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(pageBuilder: (_, __, ___) => target),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(0, _floatAnimation.value),
                    child: child,
                  ),
                  child: Image.asset('assets/newLogo.png', width: 260),
                ),
                const SizedBox(height: 24),
                const Text(
                  'REDEFINING POSTURE',
                  style: TextStyle(
                    color: Color(0xff00666D),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: const Text(
              'Made in India',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFBDBDBD),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}