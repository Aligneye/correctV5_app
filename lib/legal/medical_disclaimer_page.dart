import 'package:flutter/material.dart';
import 'package:correctv1/legal/disclaimer_content.dart';

class MedicalDisclaimerPage extends StatelessWidget {
  const MedicalDisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: scheme.onSurface,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Medical Disclaimer',
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 16),
              Text(
                'Health & Wellness Disclaimer',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 20),
              Container(
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
              const SizedBox(height: 16),
              Text(
                'Version $disclaimerVersion',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
