import 'dart:async';

import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/bluetooth/bluetooth_service_manager.dart';
import 'package:correctv1/bluetooth/device_connect_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:correctv1/home/meditation_page.dart';
import 'package:correctv1/discover/discover_page.dart';
import 'package:correctv1/home/ongoing_therapy_page.dart';
import 'package:correctv1/home/therapy_page.dart';
import 'package:correctv1/home/training_page.dart';
import 'package:correctv1/analytics/analytics_screen.dart';
import 'package:correctv1/sessions/sessions_history_page.dart';
import 'package:correctv1/settings/settings_page.dart';
import 'package:correctv1/components/nav_bar.dart';
import 'package:correctv1/calibration/calibration_manager_page.dart';
import 'package:correctv1/bluetooth/pod_disconnected_dialog.dart';
import 'package:correctv1/services/device_manager.dart';
import 'package:correctv1/services/firmware_manifest_service.dart';
import 'package:correctv1/services/session_repository.dart';
import 'package:correctv1/theme/app_theme.dart';
import 'package:correctv1/home/widgets/staggered_fade_slide.dart';
import 'package:correctv1/home/widgets/top_header_bar.dart';
import 'package:correctv1/home/widgets/posture_gauge_card.dart';
import 'package:correctv1/home/widgets/mini_ongoing_therapy_card.dart';
import 'package:correctv1/home/widgets/recent_sessions_card.dart';
import 'package:correctv1/home/widgets/connected_device_sheet.dart';
import 'package:correctv1/home/widgets/mode_control_card.dart';
import 'package:correctv1/home/widgets/quick_modes_section.dart';
import 'package:correctv1/home/widgets/stats_summary_card.dart';
import 'package:correctv1/home/widgets/streak_calendar_widget.dart';
import 'package:correctv1/home/widgets/streak_detail_sheet.dart';
import 'package:correctv1/home/widgets/xp_detail_sheet.dart';
import 'package:correctv1/home/widgets/xp_level_tile.dart';
import 'package:correctv1/services/notification_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

const _kPagePadding = EdgeInsets.fromLTRB(24, 24, 24, 100);
const _kSectionSpacing = SizedBox(height: 24);

const _kDifficultyOptions = [15, 20, 25, 30, 35, 40, 45, 50];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late PageController _pageController;
  late final List<Widget> _pages;
  int _currentIndex = 0;
  final BluetoothServiceManager _bluetoothManager = BluetoothServiceManager();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _bluetoothManager.initialize();
    WidgetsBinding.instance.addObserver(this);
    DeviceManager().init();
    _pages = [
      HomeDashboard(
        onNavigateToPage: _onItemTapped,
        onOpenTherapy: _openTherapyPage,
        onOpenTraining: _openTrainingPage,
        onOpenMeditation: _openMeditationPage,
        deviceService: _bluetoothManager.deviceService,
      ),
      const DiscoverPage(),
      const AnalyticsScreen(),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Note: We don't shutdown the Bluetooth manager here to maintain connection
    // The connection will persist across page navigations
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        physics: const BouncingScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: ModernNavBar(
        selectedIndex: _currentIndex,
        onItemSelected: _onItemTapped,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = FlutterBackgroundService();
    if (state == AppLifecycleState.paused) {
      service.startService();
    } else if (state == AppLifecycleState.resumed) {
      service.invoke('stopService');
    }
  }

  void _onItemTapped(int index) {
    final isAdjacent = (index - _currentIndex).abs() <= 1;
    setState(() {
      _currentIndex = index;
    });
    if (isAdjacent) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  Future<void> _openTherapyPage() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const TherapyPage()),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  Future<void> _openTrainingPage() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: TrainingPage(
            deviceService: BluetoothServiceManager().deviceService,
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  Future<void> _openMeditationPage() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: const MeditationPage()),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }
}

class HomeDashboard extends StatefulWidget {
  final ValueChanged<int> onNavigateToPage;
  final VoidCallback onOpenTherapy;
  final VoidCallback onOpenTraining;
  final VoidCallback onOpenMeditation;
  final AlignEyeDeviceService deviceService;

  const HomeDashboard({
    super.key,
    required this.onNavigateToPage,
    required this.onOpenTherapy,
    required this.onOpenTraining,
    required this.onOpenMeditation,
    required this.deviceService,
  });

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard>
    with SingleTickerProviderStateMixin {
  late final AlignEyeDeviceService _deviceService;
  final BluetoothServiceManager _bluetoothManager = BluetoothServiceManager();
  final DeviceManager _deviceManager = DeviceManager();
  final SessionRepository _sessionRepository = SessionRepository();
  StreamSubscription<PostureReading>? _readingSubscription;

  // _HomeDashboardState ke andar, existing fields ke neeche add karo:
  final ValueNotifier<double> postureAngleNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> isBadPostureNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> postureStatusNotifier = ValueNotifier<String>(
    'Good posture',
  );

  // double _postureAngle = 0;
  // String _postureStatus = 'Waiting for data';
  // bool _isBadPosture = false;
  // int _batteryLevel = 0;

  final _batteryLevel = ValueNotifier<int>(0);
  final ValueNotifier<int> difficultyDegNotifier = ValueNotifier<int>(25);

  ModeControlType _selectedMode = ModeControlType.track;
  PostureTimingType _selectedPostureTiming = PostureTimingType.instant;
  int _selectedDifficulty = 25;

  // Per-field pending-command guards.
  // When user taps a value, we store it here and ignore device readings for
  // that field until the device echoes back the same value (confirmation) or
  // the safety timer fires (4 s). This prevents BLE packets that arrive
  // slightly after a tap from snapping the UI back to the old value.
  ModeControlType? _pendingMode;
  Timer? _pendingModeTimer;
  PostureTimingType? _pendingPostureTiming;
  Timer? _pendingPostureTimingTimer;
  int? _pendingDifficulty;
  Timer? _pendingDifficultyTimer;

  static const _kPendingTimeout = Duration(seconds: 4);
  int _therapyDurationMinutes = 10;
  Timer? _therapyCountdownTimer;
  final _therapyRemainingSeconds = ValueNotifier<int>(0);
  Timer? _liveSessionTicker;
  String? _liveDisplaySessionId;
  final _liveDisplayDurationSec = ValueNotifier<int>(0);
  bool _liveDisplayHasFrame = false;
  bool _hasShownStartupConnectSheet = false;
  bool _isFindingDevice = false;
  bool _syncBannerDismissed = false;
  String _lastMode = '';
  bool _isLoadingOfflineSessions = false;
  int _lastSyncTick = 0;
  DateTime? _lastSessionLoadTime;
  List<SessionData> _offlineSessions = const <SessionData>[];
  TodayStats? _todayStats;
  StreakStats? _streakStats;
  bool _streakPopupCheckedThisSession = false;
  final GlobalKey _streakTileKey = GlobalKey();

  XpStats? _xpStats;
  final GlobalKey _xpTileKey = GlobalKey();
  bool _xpLevelUpCheckedThisSession = false;
  bool _weeklyRecapShownThisSession = false;

  bool _deviceInfoRequestInFlight = false;
  static final List<QuickMode> _quickModes = [
    QuickMode(
      title: 'Therapy',
      icon: Icons.graphic_eq,
      gradient: AppTheme.vibrationTherapyGradient.colors,
      targetIndex: 1,
    ),
    QuickMode(
      title: 'Training',
      icon: Icons.accessibility_new_rounded,
      gradient: AppTheme.goodPostureGradient.colors,
      targetIndex: 1,
    ),
    QuickMode(
      title: 'Walking',
      icon: Icons.directions_walk_rounded,
      gradient: AppTheme.alignWalkGradient.colors,
      targetIndex: 1,
    ),
    QuickMode(
      title: 'Breathe',
      icon: Icons.self_improvement,
      gradient: AppTheme.meditationGradient.colors,
      targetIndex: 1,
    ),
  ];

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _deviceService = widget.deviceService;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _controller.forward();

    // _readingSubscription = _deviceService.readings.listen((reading) {
    //   if (!mounted) return;
    //   final isTherapyMode = reading.mode.trim().toUpperCase() == 'THERAPY';
    //   final isLiveMode =
    //       isTherapyMode ||
    //       reading.mode.trim().toUpperCase() == 'TRAINING' ||
    //       reading.mode.trim().toUpperCase() == 'POSTURE';
    //   final reportedRemainingSec = reading.therapyRemainingSeconds;
    //   setState(() {
    //     _syncBannerDismissed = false;
    //     _postureAngle = reading.angle;
    //     _isBadPosture = reading.isBadPosture;
    //     _postureStatus = reading.isBadPosture ? 'Bad posture' : 'Good posture';
    //     _batteryLevel = reading.batteryPercentage.clamp(0, 100);
    //     _selectedMode = _modeFromDevice(reading.mode);
    //     _selectedPostureTiming = _postureTimingFromDevice(reading.subMode);
    //     _therapyDurationMinutes = _therapyMinutesFromDevice(reading.subMode);
    //     if (_kDifficultyOptions.contains(reading.difficultyDeg)) {
    //       _selectedDifficulty = reading.difficultyDeg;
    //     }
    //     if (isTherapyMode && reportedRemainingSec > 0) {
    //       // Snap countdown to firmware ground truth on every frame, then
    //       // make sure the 1 Hz local ticker is running so the number keeps
    //       // smoothly decreasing in the gap until the next BLE frame. Without
    //       // this the timer froze between frames (2-5 s of BLE jitter) and
    //       // visibly "stuck" — especially during a page transition when the
    //       // reading stream briefly pauses on the old route.
    //       _therapyRemainingSeconds = reportedRemainingSec;
    //       _ensureTherapyCountdownRunning();
    //     } else if (!isTherapyMode) {
    //       _therapyCountdownTimer?.cancel();
    //       _therapyRemainingSeconds = 0;
    //     }
    //     // Pattern names used to be mirrored into local fields here; the
    //     // mini card and ongoing page now read straight from the device
    //     // service's sticky cache, so there's nothing to do on this side.
    //     if (isLiveMode) {
    //       _snapLiveSessionDuration(reading);
    //     } else {
    //       _stopLiveSessionTicker(
    //         clearFrame: _deviceManager.activeSessionId.value == null,
    //       );
    //     }
    //   });
    // });
    _readingSubscription = _deviceService.readings.listen((reading) {
      if (!mounted) return;
      if (reading.isBadPosture != isBadPostureNotifier.value ||
          reading.mode != _lastMode) {
        FlutterBackgroundService().invoke('posture_update', {
          'is_bad_posture': reading.isBadPosture,
          'mode': reading.mode,
          'therapy_remaining': reading.therapyRemainingSeconds,
        });
        _lastMode = reading.mode;
      }
      // 🔥 [FIX]: In values ko direct update karein bina pure page ko setState se heavy re-build kiye
      postureAngleNotifier.value = reading.angle;
      isBadPostureNotifier.value = reading.isBadPosture;
      difficultyDegNotifier.value = reading.difficultyDeg;

      final postureText = reading.posture.trim();
      postureStatusNotifier.value =
          postureText.isNotEmpty && postureText.toUpperCase() != 'UNKNOWN'
          ? postureText
          : (reading.isBadPosture ? 'BAD POSTURE' : 'GOOD POSTURE');

      final isTherapyMode = reading.mode.trim().toUpperCase() == 'THERAPY';
      final isLiveMode =
          isTherapyMode ||
          reading.mode.trim().toUpperCase() == 'TRAINING' ||
          reading.mode.trim().toUpperCase() == 'POSTURE';
      final reportedRemainingSec = reading.therapyRemainingSeconds;

      _batteryLevel.value = reading.batteryPercentage.clamp(0, 100);
      final newMode = _modeFromDevice(reading.mode);
      final newTiming = _postureTimingFromDevice(reading.subMode);
      // setState(() {
      //   // _syncBannerDismissed = false;
      //
      //   // NOTE: _postureAngle, _isBadPosture, _postureStatus ko yahan se safely remove kar diya hai
      //
      //   if (modeOrTimingChanged) {
      //     _selectedMode = newMode;
      //     _selectedPostureTiming = newTiming;
      //     _therapyDurationMinutes = _therapyMinutesFromDevice(reading.subMode);
      //
      //     if (_kDifficultyOptions.contains(reading.difficultyDeg)) {
      //       _selectedDifficulty = reading.difficultyDeg;
      //     }
      //   }
      //
      //   if (isTherapyMode && reportedRemainingSec > 0) {
      //     _therapyRemainingSeconds = reportedRemainingSec;
      //     _ensureTherapyCountdownRunning();
      //   } else if (!isTherapyMode) {
      //     _therapyCountdownTimer?.cancel();
      //     _therapyRemainingSeconds = 0;
      //   }
      //
      //   if (isLiveMode) {
      //     _snapLiveSessionDuration(reading);
      //   } else {
      //     _stopLiveSessionTicker(
      //       clearFrame: _deviceManager.activeSessionId.value == null,
      //     );
      //   }
      // });
      // Compute whether anything that actually affects build() output is
      // changing. Calling setState on every BLE frame (~10/sec) rebuilds
      // this entire 6000-line widget tree and is the main cause of jank.
      bool needsRebuild = false;

      // --- Per-field confirmation checks ---
      // Each field has an optional _pending* value set when the user taps.
      // We ignore incoming device values for that field until the device
      // echoes back our selection (confirmation), then we clear the guard.
      // A safety Timer cancels the guard after _kPendingTimeout either way.

      if (_pendingMode != null && newMode == _pendingMode) {
        _pendingMode = null;
        _pendingModeTimer?.cancel();
        _pendingModeTimer = null;
      }
      if (_pendingPostureTiming != null && newTiming == _pendingPostureTiming) {
        _pendingPostureTiming = null;
        _pendingPostureTimingTimer?.cancel();
        _pendingPostureTimingTimer = null;
      }
      final incomingDifficulty = reading.difficultyDeg;
      if (_pendingDifficulty != null &&
          incomingDifficulty == _pendingDifficulty) {
        _pendingDifficulty = null;
        _pendingDifficultyTimer?.cancel();
        _pendingDifficultyTimer = null;
      }

      // Apply each field independently — only skip the field that has a live
      // pending guard; the others update freely.
      if (_pendingMode == null && _selectedMode != newMode) {
        _selectedMode = newMode;
        needsRebuild = true;
      }
      if (_pendingPostureTiming == null &&
          _selectedPostureTiming != newTiming) {
        _selectedPostureTiming = newTiming;
        _therapyDurationMinutes = _therapyMinutesFromDevice(reading.subMode);
        needsRebuild = true;
      }
      if (_pendingDifficulty == null &&
          _kDifficultyOptions.contains(incomingDifficulty) &&
          _selectedDifficulty != incomingDifficulty) {
        _selectedDifficulty = incomingDifficulty;
        needsRebuild = true;
      }
      final isIdle = reading.mode.trim().toUpperCase() == 'IDLE';

      if (isTherapyMode && reportedRemainingSec > 0) {
        final secondsChanged =
            _therapyRemainingSeconds.value != reportedRemainingSec;
        _therapyRemainingSeconds.value = reportedRemainingSec;
        _ensureTherapyCountdownRunning();
        if (secondsChanged) needsRebuild = true;
      } else if (!isTherapyMode) {
        if (_therapyCountdownTimer != null ||
            _therapyRemainingSeconds.value != 0) {
          _therapyCountdownTimer?.cancel();
          _therapyCountdownTimer = null;
          _therapyRemainingSeconds.value = 0;
          needsRebuild = true;
        }
      }

      if (isLiveMode) {
        _snapLiveSessionDuration(reading);
        needsRebuild = true;
      } else {
        final wasTicking = _liveSessionTicker != null;
        _stopLiveSessionTicker(
          clearFrame: _deviceManager.activeSessionId.value == null,
        );
        if (wasTicking) needsRebuild = true;
      }

      if (needsRebuild && mounted) {
        setState(() {});
      }
    });

    unawaited(_handleStartupDevicePrompt());
    _lastSyncTick = _deviceManager.syncCompletedTick.value;
    _deviceManager.syncCompletedTick.addListener(_handleSessionSyncFinished);
    _deviceManager.isSyncing.addListener(_handleSyncingChanged);
    _deviceManager.activeSessionId.addListener(_handleActiveSessionChanged);
    _deviceService.connectionStatus.addListener(_handleConnectionStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _printDeviceInfoStatus('startup');
      if (_deviceService.connectionStatus.value ==
          DeviceConnectionStatus.connected) {
        unawaited(_logDeviceInfoAfterConnectionDelay());
      }
    });
    unawaited(_hydrateCachedStreak());
    unawaited(_hydrateXpCache());
    unawaited(_loadOfflineSessions());
  }

  @override
  // void dispose() {
  //   _readingSubscription?.cancel();
  //   _deviceManager.syncCompletedTick.removeListener(_handleSessionSyncFinished);
  //   _deviceManager.isSyncing.removeListener(_handleSyncingChanged);
  //   _deviceManager.activeSessionId.removeListener(_handleActiveSessionChanged);
  //   _deviceService.connectionStatus.removeListener(
  //     _handleConnectionStatusChanged,
  //   );
  //   _therapyCountdownTimer?.cancel();
  //   _liveSessionTicker?.cancel();
  //   // Don't dispose the device service here - it's managed by BluetoothServiceManager
  //   // unawaited(_deviceService.dispose());
  //   _controller.dispose();
  //   super.dispose();
  // }
  @override
  void dispose() {
    _readingSubscription?.cancel();
    _deviceManager.syncCompletedTick.removeListener(_handleSessionSyncFinished);
    _deviceManager.isSyncing.removeListener(_handleSyncingChanged);
    _deviceManager.activeSessionId.removeListener(_handleActiveSessionChanged);
    _deviceService.connectionStatus.removeListener(
      _handleConnectionStatusChanged,
    );

    _therapyCountdownTimer?.cancel();
    _therapyCountdownTimer = null;
    _liveSessionTicker?.cancel();
    _liveSessionTicker = null;
    _pendingModeTimer?.cancel();
    _pendingPostureTimingTimer?.cancel();
    _pendingDifficultyTimer?.cancel();

    postureAngleNotifier.dispose();

    isBadPostureNotifier.dispose();
    postureStatusNotifier.dispose();
    _batteryLevel.dispose();
    // Don't dispose the device service here - it's managed by BluetoothServiceManager
    // unawaited(_deviceService.dispose());
    _controller.dispose();
    super.dispose();
  }

  void _handleSyncingChanged() {
    if (!mounted) return;
  }

  void _handleActiveSessionChanged() {
    if (!mounted) return;
    final id = _deviceManager.activeSessionId.value;
    if (id == null) {
      _stopLiveSessionTicker(clearFrame: true);
      unawaited(_loadOfflineSessions());
    } else {
      _liveDisplaySessionId = id;
      _syncLiveSessionTickerWithConnection();
    }
    // unawaited(_loadOfflineSessions());
  }

  void _handleConnectionStatusChanged() {
    _syncLiveSessionTickerWithConnection();
    _printDeviceInfoStatus('connection_changed');

    if (_deviceService.connectionStatus.value ==
        DeviceConnectionStatus.connected) {
      unawaited(_loadOfflineSessions());
      unawaited(_logDeviceInfoAfterConnectionDelay());
    }
  }

  Future<void> _logDeviceInfoAfterConnectionDelay() async {
    if (_deviceInfoRequestInFlight) return;
    _deviceInfoRequestInFlight = true;
    _printDeviceInfoLog('GET_DEVICE_INFO will be sent in 5 seconds');
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!mounted ||
        _deviceService.connectionStatus.value !=
            DeviceConnectionStatus.connected) {
      _deviceInfoRequestInFlight = false;
      _printDeviceInfoStatus('send_cancelled');
      return;
    }

    _printDeviceInfoLog('Sending GET_DEVICE_INFO now');
    final info = await _deviceService.getDeviceInfo();
    _deviceInfoRequestInFlight = false;
    if (info == null) {
      _printDeviceInfoLog('GET_DEVICE_INFO: no response from device');
      return;
    }
    unawaited(_checkFirmwareLatestInSupabase(info));
  }

  Future<void> _checkFirmwareLatestInSupabase(DeviceInfo info) async {
    _printDeviceInfoLog(
      'Checking Supabase firmware version for '
      'model=${info.model}, hw=${info.hardwareRevision}, fw=${info.firmwareVersion}',
    );

    final manifest = await FirmwareManifestService()
        .fetchLatestForDeviceFromSupabase(
          deviceModel: info.model,
          hardwareRevision: info.hardwareRevision,
        );

    if (manifest == null) {
      _printDeviceInfoLog(
        'Supabase firmware check: no active firmware row found for '
        'model=${info.model}, hw=${info.hardwareRevision}',
      );
      return;
    }

    final hasUpdate = FirmwareManifestService.isNewerVersion(
      manifest.latestVersion,
      info.firmwareVersion,
    );

    _printDeviceInfoLog(
      'Supabase firmware check result: '
      'current=${info.firmwareVersion}, '
      'latest=${manifest.latestVersion}, '
      'build=${manifest.buildNumber}, '
      'updateAvailable=$hasUpdate',
    );

    if (hasUpdate) {
      _printDeviceInfoLog(
        'Firmware update available: '
        'current=${info.firmwareVersion}, latest=${manifest.latestVersion}, '
        'notes=${manifest.releaseNotes.join(" | ")}, '
        'url=${manifest.firmwareUrl}',
      );
    } else {
      _printDeviceInfoLog('Firmware is latest: ${info.firmwareVersion}');
    }
  }

  void _printDeviceInfoStatus(String reason) {
    _printDeviceInfoLog(
      'Device info status [$reason]: '
      '${_deviceService.connectionStatus.value}',
    );
  }

  void _printDeviceInfoLog(String message) {
    final line = '[DEVICE_INFO] $message';
    debugPrint(line);
    // ignore: avoid_print
    print(line);
  }

  void _syncLiveSessionTickerWithConnection() {
    final connected =
        _deviceService.connectionStatus.value ==
        DeviceConnectionStatus.connected;
    final hasLiveSession = _deviceManager.activeSessionId.value != null;
    if (connected && hasLiveSession && _liveDisplayHasFrame) {
      _ensureLiveSessionTicker();
    } else {
      _liveSessionTicker?.cancel();
      _liveSessionTicker = null;
      if (mounted) setState(() {});
    }
  }

  // void _ensureLiveSessionTicker() {
  //   if (_liveSessionTicker != null) return;
  //   _liveSessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
  //     if (!mounted) {
  //       _liveSessionTicker?.cancel();
  //       _liveSessionTicker = null;
  //       return;
  //     }
  //     if (_deviceService.connectionStatus.value !=
  //             DeviceConnectionStatus.connected ||
  //         _deviceManager.activeSessionId.value == null ||
  //         !_liveDisplayHasFrame) {
  //       return;
  //     }
  //     setState(() {
  //       _liveDisplayDurationSec++;
  //     });
  //   });
  // }
  void _ensureLiveSessionTicker() {
    if (_liveSessionTicker?.isActive ?? false) return;

    // 🔥 CHANGE 1: Pehle chal rahe kisi bhi purane ticker ko safely cancel aur null karein
    _liveSessionTicker?.cancel();
    _liveSessionTicker = null;

    _liveSessionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _liveSessionTicker?.cancel();
        _liveSessionTicker = null;
        return;
      }

      // 🔥 CHANGE 2: Agar conditions follow nahi ho rahi hain, toh return karne ke bajay
      // ticker ko cancel karke band kar dein taaki battery aur memory bache.
      if (_deviceService.connectionStatus.value !=
              DeviceConnectionStatus.connected ||
          _deviceManager.activeSessionId.value == null ||
          !_liveDisplayHasFrame) {
        _liveSessionTicker?.cancel();
        _liveSessionTicker = null;
        return;
      }

      _liveDisplayDurationSec.value++;
    });
  }

  void _stopLiveSessionTicker({required bool clearFrame}) {
    _liveSessionTicker?.cancel();
    _liveSessionTicker = null;
    if (clearFrame) {
      _liveDisplayHasFrame = false;
      _liveDisplaySessionId = null;
      _liveDisplayDurationSec.value = 0;
    }
  }

  void _snapLiveSessionDuration(PostureReading reading) {
    final activeId = _deviceManager.activeSessionId.value;
    if (activeId == null) return;
    _liveDisplaySessionId = activeId;
    _liveDisplayDurationSec.value = _liveDurationFromReading(reading);
    _liveDisplayHasFrame = true;
    _ensureLiveSessionTicker();
  }

  int _liveDurationFromReading(PostureReading reading) {
    if (reading.liveSessionElapsedSeconds > 0) {
      return reading.liveSessionElapsedSeconds;
    }
    if (reading.mode.trim().toUpperCase() == 'THERAPY' &&
        reading.therapyElapsedSeconds > 0) {
      return reading.therapyElapsedSeconds;
    }
    return _liveDisplayDurationSec.value;
  }

  List<SessionData> _sessionsWithLiveDisplayDuration() {
    if (!_liveDisplayHasFrame || _liveDisplaySessionId == null) {
      return _offlineSessions;
    }
    return [
      for (final session in _offlineSessions)
        if (session.isLive && session.dbId == _liveDisplaySessionId)
          SessionData(
            id: session.id,
            dbId: session.dbId,
            type: session.type,
            name: session.name,
            time: session.time,
            date: session.date,
            duration: _formatSessionDuration(_liveDisplayDurationSec.value),
            durationSec: _liveDisplayDurationSec.value,
            alerts: session.alerts,
            score: session.score,
            pattern: session.pattern,
            wrongDurSec: session.wrongDurSec,
            isLive: session.isLive,
            tsSynced: session.tsSynced,
            cloudSynced: session.cloudSynced,
            startTs: session.startTs,
            postureEvents: session.postureEvents,
            therapyPatterns: session.therapyPatterns,
            therapyPatternEvents: session.therapyPatternEvents,
          )
        else
          session,
    ];
  }

  static String _formatSessionDuration(int durationSec) {
    if (durationSec <= 0) return '0s';
    if (durationSec < 60) return '${durationSec}s';
    final minutes = durationSec ~/ 60;
    final seconds = durationSec % 60;
    if (seconds == 0) return '$minutes min';
    return '$minutes min ${seconds}s';
  }

  void _handleSessionSyncFinished() {
    final tick = _deviceManager.syncCompletedTick.value;
    if (tick == _lastSyncTick) return;
    _lastSyncTick = tick;
    unawaited(_loadOfflineSessions());
  }

  static StatItemData _goodPostureStatItem(TodayStats? stats) {
    const gradient = AppTheme.alignWalkGradient;
    const icon = Icons.auto_awesome_rounded;
    const label = 'Good posture';

    if (stats == null) {
      return const StatItemData(
        value: '-',
        label: label,
        trendText: 'Loading…',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    if (!stats.hasTodayPostureData) {
      return const StatItemData(
        value: '—',
        label: label,
        trendText: 'Do a training',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    final String trendText;
    final bool positive;
    if (!stats.yesterdayHasPostureData) {
      trendText = 'First today';
      positive = true;
    } else if (stats.postureDeltaVsYesterday == 0) {
      trendText = 'Same';
      positive = true;
    } else {
      final delta = stats.postureDeltaVsYesterday;
      final direction = delta > 0 ? 'more' : 'less';
      trendText = '${delta.abs()}% $direction';
      positive = delta > 0;
    }

    return StatItemData(
      value: '${stats.todayPct}',
      unit: '%',
      label: label,
      trendText: trendText,
      icon: icon,
      gradient: gradient,
      positiveTrend: positive,
      trendNeutral:
          !stats.yesterdayHasPostureData || stats.postureDeltaVsYesterday == 0,
    );
  }

  static StatItemData _trackedTimeStatItem(TodayStats? stats) {
    const gradient = AppTheme.trackingGradient;
    const icon = Icons.monitor_heart_outlined;
    const label = 'Tracked time';

    if (stats == null) {
      return const StatItemData(
        value: '—',
        label: label,
        trendText: 'Loading…',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    if (!stats.hasTodayTrackedData) {
      return const StatItemData(
        value: '0',
        unit: 'min',
        label: label,
        trendText: 'No sessions',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    final display = _formatTrackedValue(stats.todayTrackedSec);

    final String trendText;
    final bool positive;
    final bool neutral;
    if (!stats.yesterdayHasTrackedData) {
      trendText = 'First today';
      positive = true;
      neutral = true;
    } else {
      final deltaSec = stats.trackedDeltaSecVsYesterday;
      if (deltaSec == 0) {
        trendText = 'Same';
        positive = true;
        neutral = true;
      } else {
        final direction = deltaSec > 0 ? 'more' : 'less';
        trendText = '${_formatDeltaDuration(deltaSec.abs())} $direction';
        positive = deltaSec > 0;
        neutral = false;
      }
    }

    return StatItemData(
      value: display.value,
      unit: display.unit,
      label: label,
      trendText: trendText,
      icon: icon,
      gradient: gradient,
      positiveTrend: positive,
      trendNeutral: neutral,
    );
  }

  static DisplayValue _formatTrackedValue(int totalSec) {
    if (totalSec < 3600) {
      final minutes = (totalSec / 60).round();
      return DisplayValue('$minutes', 'min');
    }
    final hours = totalSec / 3600.0;
    return DisplayValue(hours.toStringAsFixed(1), 'h');
  }

  static String _formatDeltaDuration(int seconds) {
    if (seconds < 3600) {
      final minutes = (seconds / 60).round();
      return '${minutes}min';
    }
    final hours = seconds / 3600.0;
    return '${hours.toStringAsFixed(1)}h';
  }

  static StatItemData _sessionsStatItem(TodayStats? stats) {
    const gradient = AppTheme.meditationGradient;
    const icon = Icons.model_training;
    const label = 'Sessions done';

    if (stats == null) {
      return const StatItemData(
        value: '—',
        label: label,
        trendText: 'Loading…',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    if (!stats.hasTodaySessions) {
      return const StatItemData(
        value: '0',
        label: label,
        trendText: 'Do a session',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    final String trendText;
    final bool positive;
    final bool neutral;
    if (!stats.yesterdayHasSessions) {
      trendText = 'First today';
      positive = true;
      neutral = true;
    } else {
      final delta = stats.sessionCountDeltaVsYesterday;
      if (delta == 0) {
        trendText = 'Same';
        positive = true;
        neutral = true;
      } else {
        final direction = delta > 0 ? 'more' : 'less';
        trendText = '${delta.abs()} $direction';
        positive = delta > 0;
        neutral = false;
      }
    }

    return StatItemData(
      value: '${stats.todaySessionCount}',
      label: label,
      trendText: trendText,
      icon: icon,
      gradient: gradient,
      positiveTrend: positive,
      trendNeutral: neutral,
    );
  }

  static StatItemData _lastSessionStatItem(
    List<SessionData> sessions,
    bool isLoading,
  ) {
    const label = 'Last session';

    if (isLoading && sessions.isEmpty) {
      return const StatItemData(
        value: '-',
        label: label,
        trendText: 'Loading...',
        icon: Icons.history_rounded,
        gradient: AppTheme.meditationGradient,
        trendNeutral: true,
      );
    }

    if (sessions.isEmpty) {
      return const StatItemData(
        value: 'None',
        label: label,
        trendText: 'Do a session',
        icon: Icons.history_rounded,
        gradient: AppTheme.meditationGradient,
        trendNeutral: true,
      );
    }

    final session = sessions.first;
    final isTraining = session.type == SessionType.posture;
    return StatItemData(
      value: isTraining ? 'Training' : 'Therapy',
      label: label,
      trendText: session.isLive ? 'Running now' : session.duration,
      icon: isTraining
          ? Icons.accessibility_new_rounded
          : Icons.graphic_eq_rounded,
      gradient: isTraining
          ? AppTheme.trainingGradient
          : AppTheme.vibrationTherapyGradient,
      trendNeutral: true,
    );
  }

  static StatItemData _therapyTimeStatItem(TodayStats? stats) {
    return _durationStatItem(
      stats: stats,
      label: 'Therapy time',
      icon: Icons.graphic_eq,
      gradient: AppTheme.vibrationTherapyGradient,
      emptyCta: 'Do a therapy',
      todaySec: stats?.todayTherapyDurationSec ?? 0,
      yesterdaySec: stats?.yesterdayTherapyDurationSec ?? 0,
      yesterdayHasData: stats?.yesterdayHasTherapyData ?? false,
    );
  }

  static StatItemData _trainingTimeStatItem(TodayStats? stats) {
    return _durationStatItem(
      stats: stats,
      label: 'Training time',
      icon: Icons.accessibility_new_rounded,
      gradient: AppTheme.trainingGradient,
      emptyCta: 'Do a training',
      todaySec: stats?.todayPostureDurationSec ?? 0,
      yesterdaySec: stats?.yesterdayPostureDurationSec ?? 0,
      yesterdayHasData: stats?.yesterdayHasPostureData ?? false,
    );
  }

  static StatItemData _durationStatItem({
    required TodayStats? stats,
    required String label,
    required IconData icon,
    required LinearGradient gradient,
    required String emptyCta,
    required int todaySec,
    required int yesterdaySec,
    required bool yesterdayHasData,
  }) {
    if (stats == null) {
      return StatItemData(
        value: '—',
        label: label,
        trendText: 'Loading…',
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    if (todaySec <= 0) {
      return StatItemData(
        value: '0',
        unit: 'min',
        label: label,
        trendText: emptyCta,
        icon: icon,
        gradient: gradient,
        trendNeutral: true,
      );
    }

    final display = _formatTrackedValue(todaySec);

    final String trendText;
    final bool positive;
    final bool neutral;
    if (!yesterdayHasData) {
      trendText = 'First today';
      positive = true;
      neutral = true;
    } else {
      final deltaSec = todaySec - yesterdaySec;
      if (deltaSec == 0) {
        trendText = 'Same';
        positive = true;
        neutral = true;
      } else {
        final direction = deltaSec > 0 ? 'more' : 'less';
        trendText = '${_formatDeltaDuration(deltaSec.abs())} $direction';
        positive = deltaSec > 0;
        neutral = false;
      }
    }

    return StatItemData(
      value: display.value,
      unit: display.unit,
      label: label,
      trendText: trendText,
      icon: icon,
      gradient: gradient,
      positiveTrend: positive,
      trendNeutral: neutral,
    );
  }

  // Future<void> _loadOfflineSessions() async {
  //   if (!mounted) return;
  //   setState(() => _isLoadingOfflineSessions = true);
  //   try {
  //     final sessions = await _sessionRepository.fetchByPeriod(
  //       'all',
  //       liveSessionId: _deviceManager.activeSessionId.value,
  //     );
  //     final todayStats = await _sessionRepository.fetchTodayStats();
  //     final streakStats = await _sessionRepository.fetchStreakStats();
  //     if (!mounted) return;
  //     debugPrint('HomeDashboard: loaded ${sessions.length} sessions');
  //     setState(() {
  //       _offlineSessions = sessions.take(5).toList(growable: false);
  //       _todayStats = todayStats;
  //       _streakStats = streakStats;
  //       _isLoadingOfflineSessions = false;
  //     });
  //     unawaited(_persistStreakCache(streakStats));
  //     unawaited(_maybeShowStreakPopup(streakStats));
  //   } catch (e) {
  //     debugPrint('HomeDashboard: _loadOfflineSessions error: $e');
  //     if (!mounted) return;
  //     setState(() {
  //       _isLoadingOfflineSessions = false;
  //     });
  //   }
  // }
  Future<void> _loadOfflineSessions() async {
    if (!mounted) return;

    final now = DateTime.now();
    if (_lastSessionLoadTime != null &&
        now.difference(_lastSessionLoadTime!).inSeconds < 5) {
      return;
    }
    _lastSessionLoadTime = now;

    if (_isLoadingOfflineSessions) return;

    if (_offlineSessions.isEmpty) {
      _isLoadingOfflineSessions = true;
      if (mounted) setState(() {});
    }

    try {
      final results = await Future.wait([
        _sessionRepository.fetchByPeriod(
          'all',
          liveSessionId: _deviceManager.activeSessionId.value,
        ),
        _sessionRepository.fetchTodayStats(),
        _sessionRepository.fetchStreakStats(),
        _sessionRepository.fetchXpStats(),
      ]);

      final List<SessionData> sessions = results[0] as List<SessionData>;
      final TodayStats? todayStats = results[1] as TodayStats?;
      final StreakStats? streakStats = results[2] as StreakStats?;
      final XpStats? xpStats = results[3] as XpStats?;

      if (!mounted) return;

      setState(() {
        _offlineSessions = sessions.take(5).toList(growable: false);
        _todayStats = todayStats;
        _streakStats = streakStats;
        _xpStats = xpStats;
        _isLoadingOfflineSessions = false;
      });

      if (streakStats != null) {
        unawaited(
          NotificationService.instance.updateStreakReminderForToday(
            streakStats.todayActive,
          ),
        );
        await _maybeShowStreakPopup(streakStats);
        unawaited(_persistStreakCache(streakStats));
      }
      if (xpStats != null) {
        unawaited(_maybeShowLevelUpPopup(xpStats));
        unawaited(_persistXpCache(xpStats));
      }
      unawaited(_maybeShowWeeklyRecap());
    } catch (e) {
      debugPrint('HomeDashboard: _loadOfflineSessions error: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingOfflineSessions = false;
      });
    }
  }

  static const String _kStreakPrefsLastDay = 'streak_popup_last_day';
  static const String _kStreakPrefsLastValue = 'streak_popup_last_value';
  static const String _kStreakPrefsCachedHighest = 'streak_cached_highest';

  static const String _kXpTotal = 'xp_total';
  static const String _kXpLevel = 'xp_level';
  static const String _kXpLastLevel = 'xp_last_level';
  static const String _kWeeklyRecapLastShownWeek = 'weekly_recap_last_shown_week';

  Future<void> _persistStreakCache(StreakStats stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kStreakPrefsLastValue, stats.currentStreak);
      await prefs.setInt(_kStreakPrefsCachedHighest, stats.highestStreak);
    } catch (e) {
      debugPrint('HomeDashboard: _persistStreakCache error: $e');
    }
  }

  Future<void> _hydrateCachedStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStreak = prefs.getInt(_kStreakPrefsLastValue) ?? 0;
      final cachedHighest = prefs.getInt(_kStreakPrefsCachedHighest) ?? 0;
      if (!mounted || _streakStats != null) return;
      setState(() {
        _streakStats = StreakStats(
          currentStreak: cachedStreak,
          highestStreak: cachedHighest,
          todayActive: false,
          todayStreakDay: DateTime.now(),
        );
      });
    } catch (e) {
      debugPrint('HomeDashboard: _hydrateCachedStreak error: $e');
    }
  }

  Future<void> _persistXpCache(XpStats stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kXpTotal, stats.totalXp);
      await prefs.setInt(_kXpLevel, stats.currentLevel);
    } catch (e) {
      debugPrint('HomeDashboard: _persistXpCache error: $e');
    }
  }

  Future<void> _hydrateXpCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedLevel = prefs.getInt(_kXpLevel) ?? 1;
      final cachedTotal = prefs.getInt(_kXpTotal) ?? 0;
      if (!mounted || _xpStats != null) return;
      // Reconstruct minimal XpStats from cache
      final xpForCurrent = cachedLevel * cachedLevel * 100;
      final xpForNext = (cachedLevel + 1) * (cachedLevel + 1) * 100;
      setState(() {
        _xpStats = XpStats(
          totalXp: cachedTotal,
          currentLevel: cachedLevel,
          xpForCurrentLevel: xpForCurrent,
          xpForNextLevel: xpForNext,
        );
      });
    } catch (e) {
      debugPrint('HomeDashboard: _hydrateXpCache error: $e');
    }
  }

  Future<void> _maybeShowLevelUpPopup(XpStats stats) async {
    if (_xpLevelUpCheckedThisSession) return;
    _xpLevelUpCheckedThisSession = true;

    final prefs = await SharedPreferences.getInstance();
    final lastLevel = prefs.getInt(_kXpLastLevel) ?? 0;

    if (lastLevel == 0) {
      // First run — just record the level, no popup
      await prefs.setInt(_kXpLastLevel, stats.currentLevel);
      return;
    }

    if (stats.currentLevel <= lastLevel) return;

    await prefs.setInt(_kXpLastLevel, stats.currentLevel);

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => LevelUpPopup(
          xpStats: stats,
          resolveTarget: _resolveXpTileRect,
        ),
      );
    });
  }

  Rect? _resolveXpTileRect() {
    final ctx = _xpTileKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  Future<void> _maybeShowWeeklyRecap() async {
    if (_weeklyRecapShownThisSession) return;

    final now = DateTime.now();
    // Only trigger on Mondays
    if (now.weekday != DateTime.monday) return;

    final prefs = await SharedPreferences.getInstance();
    final lastShownWeek = prefs.getString(_kWeeklyRecapLastShownWeek) ?? '';
    final thisWeekKey = _isoWeekKey(now);

    if (lastShownWeek == thisWeekKey) return;

    _weeklyRecapShownThisSession = true;

    WeeklyRecap recap;
    List<int> calendarDays;
    try {
      final results = await Future.wait([
        _sessionRepository.fetchWeeklyRecap(),
        _sessionRepository.fetchStreakCalendar(
          35,
          freezeUsedDays: _streakStats?.freezeUsedDays ?? [],
        ),
      ]);
      recap = results[0] as WeeklyRecap;
      calendarDays = results[1] as List<int>;
    } catch (e) {
      debugPrint('HomeDashboard: _maybeShowWeeklyRecap fetch error: $e');
      return;
    }

    await prefs.setString(_kWeeklyRecapLastShownWeek, thisWeekKey);

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _WeeklyRecapSheet(
          recap: recap,
          streakDays: _streakStats?.currentStreak ?? 0,
          calendarDays: calendarDays,
        ),
      );
    });
  }

  static String _isoWeekKey(DateTime date) {
    // ISO week: year + week number
    final dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays + 1;
    final weekNumber = ((dayOfYear - date.weekday + 10) / 7).floor();
    return '${date.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  Future<void> _maybeShowStreakPopup(StreakStats stats) async {
    if (_streakPopupCheckedThisSession) return;
    _streakPopupCheckedThisSession = true;

    final prefs = await SharedPreferences.getInstance();
    final lastDayStr = prefs.getString(_kStreakPrefsLastDay);
    final lastValue = prefs.getInt(_kStreakPrefsLastValue) ?? 0;

    final todayKey = _streakDayKey(stats.todayStreakDay);
    if (lastDayStr == todayKey) {
      return; // already shown this streak day
    }

    final kind = _classifyStreakEvent(
      previousStreak: lastValue,
      currentStreak: stats.currentStreak,
    );

    await prefs.setString(_kStreakPrefsLastDay, todayKey);
    await prefs.setInt(_kStreakPrefsLastValue, stats.currentStreak);

    if (kind == null || !mounted) return;

    // Defer to post-frame so we don't fight the initial build animations.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => StreakPopup(
          stats: stats,
          kind: kind,
          resolveTarget: _resolveStreakTileRect,
        ),
      );
    });
  }

  Rect? _resolveStreakTileRect() {
    final ctx = _streakTileKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  void _showStreakDetailSheet() {
    final stats = _streakStats;
    if (stats == null || !mounted) return;
    showStreakDetailSheet(
      context,
      streakStats: stats,
      repository: _sessionRepository,
    );
  }

  void _showXpDetailSheet() {
    final stats = _xpStats;
    if (stats == null || !mounted) return;
    showXpDetailSheet(
      context,
      xpStats: stats,
      repository: _sessionRepository,
    );
  }

  static String _streakDayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static StreakPopupKind? _classifyStreakEvent({
    required int previousStreak,
    required int currentStreak,
  }) {
    if (currentStreak > previousStreak) return StreakPopupKind.increased;
    if (currentStreak < previousStreak) return StreakPopupKind.broken;
    return null; // unchanged — no popup
  }

  /// Therapy is "live" from the home-page perspective when the device is in
  /// therapy mode and we still have time on the clock. Used to swap the
  /// live-posture card for a compact ongoing-therapy preview.
  bool get _isTherapyLive =>
      _selectedMode == ModeControlType.therapy &&
      _therapyRemainingSeconds.value > 0;

  /// Idempotent: spin up the 1 Hz ticker if it isn't already alive. Called
  /// from the BLE reading handler on every frame so the countdown keeps
  /// advancing smoothly between frames instead of freezing until the next
  /// firmware packet arrives.
  void _ensureTherapyCountdownRunning() {
    if (_therapyCountdownTimer?.isActive ?? false) return;
    _therapyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_therapyRemainingSeconds.value <= 1) {
        timer.cancel();
        _therapyRemainingSeconds.value = 0;
        return;
      }
      _therapyRemainingSeconds.value -= 1;
    });
  }

  void _stopTherapyCountdown({bool clearTime = false}) {
    _therapyCountdownTimer?.cancel();
    if (clearTime) {
      _therapyRemainingSeconds.value = 0;
    }
  }

  Future<void> _handleDeviceStatusTap() async {
    final status = _deviceService.connectionStatus.value;

    // When already connected, show the management sheet. In every other
    // state (including while an auto-connect attempt is in flight) tapping
    // the pill should take the user straight to the connect page — it will
    // surface the ongoing attempt and auto-pop once the pod is connected.
    if (status == DeviceConnectionStatus.connected) {
      await _showConnectedSheet();
      return;
    }

    if (!mounted) return;

    if (!await _ensureBleReady()) return;

    if (!mounted) return;
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const DeviceConnectPage()));
  }

  /// Ensures Bluetooth is on and permissions are granted before proceeding.
  /// Returns `true` when BLE is ready; `false` if the user declined or
  /// something couldn't be resolved.
  Future<bool> _ensureBleReady() async {
    final readiness = await _deviceService.checkReadiness();
    if (!mounted) return false;

    switch (readiness) {
      case BleReadiness.ready:
        return true;

      case BleReadiness.bluetoothUnsupported:
        _showBleSnackBar('Bluetooth is not supported on this device.');
        return false;

      case BleReadiness.bluetoothOff:
        try {
          // On Android this surfaces the native "Allow app to turn on
          // Bluetooth?" system dialog — no custom prompt needed.
          await FlutterBluePlus.turnOn();

          // Wait for the adapter to actually come up (the user might still be
          // looking at the system dialog, so poll for a few seconds).
          final on = await FlutterBluePlus.adapterState
              .where((s) => s == BluetoothAdapterState.on)
              .first
              .timeout(const Duration(seconds: 8));
          if (on == BluetoothAdapterState.on) return true;
        } catch (_) {
          // User declined the system dialog or timeout.
        }
        if (!mounted) return false;
        _showBleSnackBar(
          'Bluetooth is required to connect. Please enable it and try again.',
        );
        return false;

      case BleReadiness.permissionDenied:
        _showBleSnackBar(
          'Bluetooth permissions are required. Please grant them and try again.',
        );
        return false;

      case BleReadiness.permissionPermanentlyDenied:
        if (!mounted) return false;
        _showBleSnackBar(
          'Bluetooth permissions were denied. Opening settings…',
        );
        await openAppSettings();
        return false;
    }
  }

  void _showBleSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _showConnectedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ConnectedDeviceSheet(
        batteryLevel: _batteryLevel.value,
        profile: _deviceService.activeProfileName.value,
        onDisconnect: () async {
          Navigator.of(ctx).pop();
          await BluetoothServiceManager.instance.disconnectByUser();
        },
        onForget: () async {
          Navigator.of(ctx).pop();
          await BluetoothServiceManager.instance.forgetDevice();
          if (!mounted) return;
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const DeviceConnectPage()),
          );
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Future<void> _handleStartupDevicePrompt() async {
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted || _hasShownStartupConnectSheet) {
      return;
    }

    if (_deviceService.connectionStatus.value !=
        DeviceConnectionStatus.disconnected) {
      return;
    }

    final hasBondedTarget = await _deviceService.hasBondedTargetDevice();
    if (!mounted || hasBondedTarget) {
      return;
    }

    if (_deviceService.connectionStatus.value !=
        DeviceConnectionStatus.disconnected) {
      return;
    }

    setState(() {
      _isFindingDevice = true;
    });
    bool hasUnpairedNearby = false;
    try {
      hasUnpairedNearby = await _deviceService.hasUnpairedTargetDeviceNearby(
        timeout: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFindingDevice = false;
        });
      }
    }
    if (!mounted || !hasUnpairedNearby) {
      return;
    }

    _hasShownStartupConnectSheet = true;
    await _showStartupConnectBottomSheet();
  }

  Future<void> _showStartupConnectBottomSheet() {
    bool isConnecting = false;
    const popupPrimary = AppTheme.brandPrimary;
    const popupSecondaryBg = AppTheme.connectedBg;
    return showModalBottomSheet<void>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          'Align Pod',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Straighten up. Your future self will thank you.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            final scale = 0.92 + (0.08 * value);
                            return Opacity(
                              opacity: value.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/product.png',
                              height: 170,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isConnecting
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                backgroundColor: popupSecondaryBg,
                                foregroundColor: popupPrimary,
                                side: const BorderSide(color: popupPrimary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Not now'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isConnecting
                                  ? null
                                  : () {
                                      setModalState(() => isConnecting = true);
                                      Navigator.of(context).pop();
                                      unawaited(_handleDeviceStatusTap());
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: popupPrimary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isConnecting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Connect'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _syncModeControlToDevice({
    required ModeControlType mode,
    required PostureTimingType postureTiming,
    required int therapyDurationMinutes,
    required int difficultyDegrees,
  }) async {
    final modeLabel = switch (mode) {
      ModeControlType.track => 'IDLE',
      ModeControlType.posture => 'TRAINING',
      ModeControlType.therapy => 'THERAPY',
    };
    final timingLabel = switch (postureTiming) {
      PostureTimingType.instant => 'INSTANT',
      PostureTimingType.delayed => 'DELAYED',
      PostureTimingType.automatic => 'AUTOMATIC',
    };

    await _deviceService.sendModeControl(
      mode: modeLabel,
      postureTiming: timingLabel,
      therapyDurationMinutes: therapyDurationMinutes,
      difficultyDegrees: difficultyDegrees,
    );
  }

  /// Variant for the mini card tap: therapy is already running on the pod,
  /// so we just navigate without re-issuing start/prime commands.
  void _openOngoingTherapyFromHome() {
    if (_deviceService.connectionStatus.value !=
        DeviceConnectionStatus.connected) {
      return;
    }
    _pushOngoingTherapyPage(intensity: 2);
  }

  void _pushOngoingTherapyPage({required int intensity}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) =>
            OngoingTherapyPage(
              deviceService: _deviceService,
              durationMinutes: _therapyDurationMinutes,
              intensity: intensity,
              targetPointName: 'Default',
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1)
                  .chain(CurveTween(curve: Curves.easeOutCubic))
                  .animate(animation),
              child: child,
            ),
          );
        },
      ),
    );
  }

  // ModeControlType _modeFromDevice(String mode) {
  //   final normalized = mode.trim().toUpperCase();
  //   if (normalized == 'TRAINING' || normalized == 'POSTURE') {
  //     return ModeControlType.posture;
  //   }
  //   if (normalized == 'THERAPY') {
  //     return ModeControlType.therapy;
  //   }
  //   return ModeControlType.track;
  // }
  ModeControlType _modeFromDevice(String mode) {
    final normalized = mode.trim().toUpperCase();
    if (normalized == 'TRAINING' || normalized == 'POSTURE') {
      return ModeControlType.posture;
    }
    if (normalized == 'THERAPY') {
      return ModeControlType.therapy;
    }
    return ModeControlType.track;
  }

  PostureTimingType _postureTimingFromDevice(String subMode) {
    final normalized = subMode.trim().toUpperCase();
    if (normalized == 'DELAYED') {
      return PostureTimingType.delayed;
    }
    if (normalized == 'AUTOMATIC') {
      return PostureTimingType.automatic;
    }
    return PostureTimingType.instant;
  }

  int _therapyMinutesFromDevice(String subMode) {
    final minutes = int.tryParse(subMode.split(' ').first.trim());
    if (minutes == 10 || minutes == 20 || minutes == 30) {
      return minutes!;
    }
    return _therapyDurationMinutes;
  }

  void _showAllModesSheet(BuildContext context) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final scheme = Theme.of(sheetCtx).colorScheme;
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) =>
                              AppTheme.brandGradient.createShader(bounds),
                          blendMode: BlendMode.srcIn,
                          child: const Text(
                            'All Modes',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(sheetCtx),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.1,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Choose your training mode',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      children: [
                        _AllModesSheetItem(
                          title: 'Tracking mode',
                          subtitle: 'Monitor your posture in real-time',
                          icon: Icons.monitor_heart_outlined,
                          gradient: AppTheme.trackingGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                          },
                        ),
                        const SizedBox(height: 12),
                        _AllModesSheetItem(
                          title: 'Posture training mode',
                          subtitle: 'Basic, Intermediate & Advanced levels',
                          icon: Icons.accessibility_new_rounded,
                          gradient: AppTheme.goodPostureGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            widget.onOpenTraining();
                          },
                        ),
                        const SizedBox(height: 12),
                        _AllModesSheetItem(
                          title: 'Vibration therapy mode',
                          subtitle: 'Acupressure vibration therapy',
                          icon: Icons.graphic_eq,
                          gradient: AppTheme.vibrationTherapyGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            widget.onOpenTherapy();
                          },
                        ),
                        const SizedBox(height: 12),
                        _AllModesSheetItem(
                          title: 'Breathe mode',
                          subtitle: 'Rhythmic breathing guidance',
                          icon: Icons.self_improvement,
                          gradient: AppTheme.meditationGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            widget.onOpenMeditation();
                          },
                        ),
                        const SizedBox(height: 12),
                        _AllModesSheetItem(
                          title: 'Walking mode',
                          subtitle: 'Walking posture trainer',
                          icon: Icons.directions_walk,
                          gradient: AppTheme.alignWalkGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                          },
                        ),
                        const SizedBox(height: 12),
                        _AllModesSheetItem(
                          title: 'Analytics',
                          subtitle: 'Track your posture progress',
                          icon: Icons.bar_chart_rounded,
                          gradient: AppTheme.ridingGradient,
                          onTap: () {
                            Navigator.pop(sheetCtx);
                            widget.onNavigateToPage(2);
                          },
                        ),
                        const SizedBox(height: 20),
                        const QuickModeProTipCard(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.pageBackgroundGradientFor(context),
      ),
      child: SafeArea(
        bottom: false, // Let content flow behind navbar
        child: SingleChildScrollView(
          padding: _kPagePadding, // Extra bottom padding for navbar
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 0,
                child: ValueListenableBuilder<DeviceConnectionStatus>(
                  valueListenable: _deviceService.connectionStatus,
                  builder: (context, connectionStatus, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _deviceManager.isSyncing,
                      builder: (context, isSyncing, child) {
                        return ValueListenableBuilder<String?>(
                          valueListenable: _deviceManager.activeSessionId,
                          builder: (context, activeSessionId, child) {
                            return ValueListenableBuilder<String>(
                              valueListenable: _deviceService.activeProfileName,
                              builder: (context, profile, child) {
                                return TopHeaderBar(
                                  status: connectionStatus,
                                  isFindingDevice: _isFindingDevice,
                                  isSyncing: isSyncing,
                                  isLive:
                                      connectionStatus ==
                                          DeviceConnectionStatus.connected &&
                                      activeSessionId != null,
                                  batteryLevel: _batteryLevel.value,
                                  profile: profile,
                                  onTap: _handleDeviceStatusTap,
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 100,
                child: StatsSummaryCard(
                  streakDays: _streakStats?.currentStreak ?? 0,
                  streakTodayActive: _streakStats?.todayActive ?? false,
                  streakTileKey: _streakTileKey,
                  freezeTokens: _streakStats?.freezeTokens ?? 0,
                  xpStats: _xpStats,
                  xpTileKey: _xpTileKey,
                  onStreakTap: _streakStats != null
                      ? () => _showStreakDetailSheet()
                      : null,
                  onXpTap: _xpStats != null
                      ? () => _showXpDetailSheet()
                      : null,
                  items: [
                    _lastSessionStatItem(
                      _offlineSessions,
                      _isLoadingOfflineSessions,
                    ),
                    _goodPostureStatItem(_todayStats),
                    _trainingTimeStatItem(_todayStats),
                    _therapyTimeStatItem(_todayStats),
                    _sessionsStatItem(_todayStats),
                    _trackedTimeStatItem(_todayStats),
                  ],
                ),
              ),
              _kSectionSpacing,
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 200,
                // While therapy is in progress, swap the live-posture card
                // out for a compact preview of the ongoing therapy session —
                // tap it to jump into the full immersive page.
                child: _isTherapyLive
                    ? MiniOngoingTherapyCard(
                        deviceService: _deviceService,
                        totalMinutes: _therapyDurationMinutes,
                        onTap: _openOngoingTherapyFromHome,
                      )
                    // : PostureGaugeCard(
                    //     postureAngle: _postureAngle,
                    //     postureStatus: _postureStatus,
                    //     isBadPosture: _isBadPosture,
                    //     controller: _controller,
                    //   ),
                    : ValueListenableBuilder<double>(
                        valueListenable: postureAngleNotifier,

                        builder: (context, angle, _) =>
                            ValueListenableBuilder<bool>(
                              valueListenable: isBadPostureNotifier,

                              builder: (context, isBad, _) =>
                                  ValueListenableBuilder<String>(
                                    valueListenable: postureStatusNotifier,

                                    builder: (context, status, _) =>
                                        ValueListenableBuilder<int>(
                                          valueListenable:
                                              difficultyDegNotifier,

                                          builder: (context, diff, _) =>
                                              PostureGaugeCard(
                                                postureAngle: angle,
                                                postureStatus: status,
                                                isBadPosture: isBad,
                                                difficultyDeg: diff,
                                                controller: _controller,
                                              ),
                                        ),
                                  ),
                            ),
                      ),
              ),
              _kSectionSpacing,
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 300,
                child: ModeControlCard(
                  selectedMode: _selectedMode,
                  selectedPostureTiming: _selectedPostureTiming,
                  selectedDifficulty: _selectedDifficulty,
                  onModeSelected: (mode) {
                    setState(() => _selectedMode = mode);
                    _pendingMode = mode;
                    _pendingModeTimer?.cancel();
                    // IDLE guard has no timer: device won't confirm IDLE while a
                    // live session is active, so we hold the guard until the user
                    // explicitly picks a different mode (which overwrites _pendingMode).
                    // For posture/therapy, a 4s safety timer is enough because those
                    // modes are actually confirmed by the device quickly.
                    if (mode != ModeControlType.track) {
                      _pendingModeTimer = Timer(_kPendingTimeout, () {
                        _pendingMode = null;
                        _pendingModeTimer = null;
                      });
                    }
                    _stopTherapyCountdown();
                    unawaited(
                      _syncModeControlToDevice(
                        mode: mode,
                        postureTiming: _selectedPostureTiming,
                        therapyDurationMinutes: _therapyDurationMinutes,
                        difficultyDegrees: _selectedDifficulty,
                      ),
                    );
                  },
                  onPostureTimingSelected: (timing) {
                    setState(() => _selectedPostureTiming = timing);
                    _pendingPostureTiming = timing;
                    _pendingPostureTimingTimer?.cancel();
                    _pendingPostureTimingTimer = Timer(_kPendingTimeout, () {
                      _pendingPostureTiming = null;
                      _pendingPostureTimingTimer = null;
                    });
                    unawaited(
                      _syncModeControlToDevice(
                        mode: _selectedMode,
                        postureTiming: timing,
                        therapyDurationMinutes: _therapyDurationMinutes,
                        difficultyDegrees: _selectedDifficulty,
                      ),
                    );
                  },
                  onDifficultySelected: (difficulty) {
                    setState(() => _selectedDifficulty = difficulty);
                    _pendingDifficulty = difficulty;
                    _pendingDifficultyTimer?.cancel();
                    _pendingDifficultyTimer = Timer(_kPendingTimeout, () {
                      _pendingDifficulty = null;
                      _pendingDifficultyTimer = null;
                    });
                    unawaited(
                      _syncModeControlToDevice(
                        mode: _selectedMode,
                        postureTiming: _selectedPostureTiming,
                        therapyDurationMinutes: _therapyDurationMinutes,
                        difficultyDegrees: difficulty,
                      ),
                    );
                  },
                ),
              ),
              _kSectionSpacing,
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 350,
                child: QuickModesSection(
                  modes: _quickModes,
                  onViewAll: () => _showAllModesSheet(context),
                  onModeTap: widget.onNavigateToPage,
                  onTherapyModeTap: widget.onOpenTherapy,
                  onTrainingModeTap: widget.onOpenTraining,
                  onMeditationModeTap: widget.onOpenMeditation,
                ),
              ),
              _kSectionSpacing,
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 400,
                child: CalibrationCard(
                  onCalibratePressed: () async {
                    if (_deviceService.connectionStatus.value !=
                        DeviceConnectionStatus.connected) {
                      await showPodDisconnectedDialog(context);
                      return;
                    }
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => CalibrationManagerPage(
                          deviceService: _deviceService,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    if (result == true) {
                      widget.onNavigateToPage(0);
                    }
                  },
                ),
              ),
              _kSectionSpacing,
              StaggeredFadeSlide(
                controller: _controller,
                delayMs: 500,
                child: ValueListenableBuilder<DeviceConnectionStatus>(
                  valueListenable: _deviceService.connectionStatus,
                  builder: (context, status, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _deviceManager.isSyncing,
                      builder: (context, isSyncing, _) {
                        return RecentSessionsCard(
                          sessions: _sessionsWithLiveDisplayDuration(),
                          isLoading: _isLoadingOfflineSessions,
                          isSyncing: isSyncing,
                          isDeviceDisconnected:
                              status == DeviceConnectionStatus.disconnected &&
                              !_syncBannerDismissed,
                          isDeviceConnecting:
                              status == DeviceConnectionStatus.connecting,
                          onViewAll: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => const SessionsHistoryPage(),
                            ),
                          ),
                          onSessionTap: (session) =>
                              showSessionDetailSheet(context, session: session),
                          onSyncNow: () => unawaited(_handleSyncNow()),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSyncNow() async {
    final status = _deviceService.connectionStatus.value;
    if (status == DeviceConnectionStatus.connected) {
      return;
    }
    try {
      await _bluetoothManager.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncBannerDismissed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bluetooth connection cancelled. '
            'Tap the connect button when ready.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}



/// Compact preview of an in-progress therapy session shown in the home
/// dashboard in place of the live-posture gauge. Mirrors the visual language
/// of [OngoingTherapyPage] — soft pink gradient, gentle breathing orb —
/// while staying small enough to sit in the stats column. Tapping anywhere
/// on the card opens the full immersive page.


class _WeeklyRecapSheet extends StatelessWidget {
  const _WeeklyRecapSheet({
    required this.recap,
    required this.streakDays,
    required this.calendarDays,
  });

  final WeeklyRecap recap;
  final int streakDays;
  final List<int> calendarDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Last Week Recap',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _RecapStat(
                  label: 'Active Days',
                  value: '${recap.activeDays}/${recap.totalDays}',
                  icon: Icons.calendar_today_rounded,
                  color: const Color(0xFFA855F7),
                ),
                const SizedBox(width: 12),
                _RecapStat(
                  label: 'XP Earned',
                  value: '${recap.totalXpThisWeek}',
                  icon: Icons.star_rounded,
                  color: const Color(0xFFEC4899),
                ),
                const SizedBox(width: 12),
                _RecapStat(
                  label: 'Streak',
                  value: '$streakDays days',
                  icon: Icons.local_fire_department_rounded,
                  color: const Color(0xFFF97316),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Activity Heatmap',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            StreakCalendarWidget(dayStates: calendarDays),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFA855F7), Color(0xFFEC4899)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Keep it up this week!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
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
    );
  }
}

class _RecapStat extends StatelessWidget {
  const _RecapStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllModesSheetItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _AllModesSheetItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}


