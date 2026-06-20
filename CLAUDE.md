# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AlignEye — a Flutter mobile app for posture correction and health tracking with BLE device integration. Package name is `correctv1`. Backend is Supabase (PostgreSQL + Auth). Local storage uses SQLite via sqflite.

## Common Commands

```bash
# Run the app (Supabase keys passed via dart-define)
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY

# Run without Supabase (shows config screen, can continue as guest)
flutter run

# Static analysis
flutter analyze

# Run tests
flutter test

# Get dependencies
flutter pub get

# Generate app icons (after changing assets/appIcon.png)
flutter pub run flutter_launcher_icons
```

## Architecture

### App Entry & Routing
`main.dart` initializes Supabase, SessionDatabase, SessionSyncService, and BackgroundService, then routes through `AuthGate` (or a config-missing fallback page). Navigation uses `MaterialPageRoute` pushes — no declarative router.

### Key Service Layer (`lib/services/`)
- **SessionDatabase** — SQLite CRUD for session data
- **SessionRepository** — syncs local sessions to Supabase
- **SessionSyncService** — orchestrates background sync
- **LiveSessionRecorder** — records real-time posture data from BLE
- **BleSessionSync** — pipeline between BLE telemetry and database
- **BackgroundService** — keeps the app alive when backgrounded (flutter_background_service)
- **DeviceManager** — manages BLE device state

### BLE Communication (`lib/bluetooth/`)
- **AligneyeDeviceService** — full device protocol: commands, telemetry parsing, calibration data
- **BluetoothServiceManager** — wraps flutter_blue_plus for discovery/connection
- **DeviceConnectPage** — UI for scanning and pairing

### Auth (`lib/auth/`)
Supabase Auth with email/password and Google OAuth. `AuthGate` decides whether to show login or home. If Supabase keys are missing at build time, app can still run in guest mode.

### Data Flow
BLE device → AligneyeDeviceService (parse) → LiveSessionRecorder → SessionDatabase (SQLite) → SessionRepository → Supabase (remote sync)

### Database Schema (Supabase)
Two tables with RLS scoped to `auth.uid()`:
- **sessions** — posture/therapy sessions with JSONB event arrays
- **user_streaks** — current_streak, highest_streak, last_active_day

## Design System

Follow `DESIGN_SYSTEM.md` for all UI work. Key rules:

- All primary/filled buttons use the purple→pink gradient: `[Color(0xFFA855F7), Color(0xFFEC4899)]`
- Dark immersive backgrounds use `Color(0xFF0D1A1D)`
- Home feature modules (Walking, Breathe, Therapy, Training, Tracking, Analytics) must share one consistent icon/card visual system
- Theme tokens live in `lib/theme/app_theme.dart`
- Motion: fast 180ms, standard 300ms, screen 400ms, curve `Curves.easeOutCubic`
- Text scaling is disabled app-wide (TextScaler.noScaling in MaterialApp builder)

## Project-Specific Notes

- The app uses Material Design 3 (`useMaterial3: true`) with custom light and dark themes
- Flutter SDK constraint: ^3.9.2
- Min Android SDK: 21
- Supabase project ID: `correctv1`
- OAuth redirect URL: `io.supabase.flutter://login-callback/`
- BLE logging is disabled in production (`FlutterBluePlus.setLogLevel(LogLevel.none)`)
- Assets are in `assets/` — appIcon.png, logosvg.svg, product.png