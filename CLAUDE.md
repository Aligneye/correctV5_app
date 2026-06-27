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

# Run a single test file
flutter test test/widget_test.dart

# Get dependencies
flutter pub get

# Generate app icons (after changing assets/appIcon.png)
flutter pub run flutter_launcher_icons
```

## Architecture

### App Entry & Routing
`main.dart` initializes Supabase, SessionDatabase, SessionSyncService, and BackgroundService, then routes through `AuthGate` (or a config-missing fallback page). Navigation uses `MaterialPageRoute` pushes — no declarative router. The home page uses a `PageController` with a bottom nav bar (`lib/components/nav_bar.dart`) for top-level tabs.

### Singleton Pattern
Most services use private-constructor singletons (`ClassName._()` + `static final instance`). `DeviceManager` uses a factory constructor pointing to a private static. These are initialized in `main()` and accessed globally — no DI framework.

### Key Service Layer (`lib/services/`)
- **SessionDatabase** — SQLite CRUD for session data (version 3, with migration path)
- **SessionRepository** — read-only query layer over SQLite, scoped to `auth.uid()`; local DB is source of truth for reads
- **SessionSyncService** — orchestrates background sync to Supabase
- **LiveSessionRecorder** — records real-time posture data from BLE stream; auto-creates/finishes sessions based on device mode transitions; minimum session duration 30s, 5s update interval, 7s grace period before finishing
- **BleSessionSync** — pipeline between BLE telemetry and database
- **BackgroundService** — keeps the app alive when backgrounded (flutter_background_service)
- **DeviceManager** — app-wide glue between Bluetooth and session-sync layers; defers BLE backlog sync during live sessions

### Firmware OTA (`lib/services/`)
- **FirmwareManifestService** — fetches latest firmware metadata from `firmware_releases` Supabase table
- **FirmwareDownloadService** — downloads firmware ZIP with SHA-256 verification
- **FirmwareUpdateService** — state machine (idle→checking→downloading→ready→noUpdate/error); auto-checks on device connect
- **DfuUpdateService** — wraps `nordic_dfu` for actual DFU flashing
- **FirmwareUpdatePage** (`lib/settings/`) — UI for the update flow

### BLE Communication (`lib/bluetooth/`)
- **AligneyeDeviceService** — full device protocol: commands, telemetry parsing, calibration data. Uses a single GATT characteristic (`beb5483e-...`) on service `4fafc201-...`. Scans for devices with name prefix "align pod"
- **BluetoothServiceManager** — wraps flutter_blue_plus for discovery/connection
- **DeviceConnectPage** — UI for scanning and pairing

Device modes: `IDLE`, `TRAINING`, `THERAPY` (legacy `OFF`/`TRACKING`/`POSTURE` mapped for backward compat via `normalizeDeviceMode()`)

### Calibration (`lib/calibration/`)
- **CalibrationPage** — multi-stage flow (intro→starting→getReady→holdStill→success/failed/disconnected) with animation controllers and device command integration
- **CalibrationManagerPage** — profile management wrapper around calibration

### Auth (`lib/auth/`)
Supabase Auth with email/password and Google OAuth. `AuthGate` decides whether to show login or home. If Supabase keys are missing at build time, app can still run in guest mode.

### Data Flow
BLE device → AligneyeDeviceService (parse `PostureReading`) → LiveSessionRecorder (mode-transition detection) → SessionDatabase (SQLite) → SessionSyncService → Supabase (remote sync)

### Database Schema (Supabase)
Schema lives in `lib/supabase/schema.sql` with migrations in `lib/supabase/migrations/`. Three tables with RLS:
- **sessions** — posture/therapy sessions with JSONB event arrays; idempotent on (user_id, start_ts, type)
- **user_streaks** — current_streak, highest_streak, last_active_day (client-computed, persisted for instant rendering)
- **firmware_releases** — published firmware versions; public SELECT, admin-only writes

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
- Default Supabase URL is hardcoded in `main.dart` as fallback — `--dart-define` overrides it
- OAuth redirect URL: `io.supabase.flutter://login-callback/`
- BLE logging is disabled in production (`FlutterBluePlus.setLogLevel(LogLevel.none)`)
- Assets are in `assets/` — appIcon.png, logosvg.svg, product.png
- Lints: uses `package:flutter_lints/flutter.yaml` (default rules, no custom overrides)
