import 'dart:async';
import 'package:flutter/material.dart';
import 'package:correctv1/legal/disclaimer_content.dart';
import 'package:correctv1/legal/disclaimer_prefs.dart';
import 'package:correctv1/legal/disclaimer_sync_service.dart';

class DisclaimerGatePage extends StatelessWidget {
  final Widget nextScreen;

  const DisclaimerGatePage({super.key, required this.nextScreen});

  Future<void> _onAccept(BuildContext context) async {
    await DisclaimerPrefs.markAccepted();
    unawaited(DisclaimerSyncService.syncIfNeeded());
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => nextScreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.health_and_safety_outlined,
                  color: scheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Health & Wellness\nDisclaimer',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please read before continuing',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? scheme.surfaceContainerHighest
                        : scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      disclaimerText,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA855F7).withValues(alpha: 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _onAccept(context),
                      child: const Center(
                        child: Text(
                          'I Understand & Agree',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

