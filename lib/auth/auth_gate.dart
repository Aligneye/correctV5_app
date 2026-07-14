import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:correctv1/auth/login_page.dart';
import 'package:correctv1/home/home_page.dart';
import 'package:correctv1/legal/disclaimer_sync_service.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          unawaited(DisclaimerSyncService.syncIfNeeded());
          return const HomePage();
        }
        return const LoginPage();
      },
    );
  }
}
