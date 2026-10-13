import 'dart:async';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/services/ble_session_sync.dart';
import 'package:flutter/foundation.dart';

/// Singleton manager for maintaining Bluetooth connection across the app
class BluetoothServiceManager {
  static final BluetoothServiceManager _instance =
      BluetoothServiceManager._internal();
  factory BluetoothServiceManager() => _instance;
  BluetoothServiceManager._internal();

  static BluetoothServiceManager get instance => _instance;

  final AlignEyeDeviceService _deviceService = AlignEyeDeviceService();

  AlignEyeDeviceService get deviceService => _deviceService;

  /// Initialize and start maintaining the Bluetooth connection
  Future<void> initialize() async {
    debugPrint('=== BluetoothServiceManager: Initializing ===');
    // Auto-connect and auto-reconnect are disabled.
    debugPrint(
      '=== BluetoothServiceManager: Initialization complete ===',
    );
  }

  /// Stop maintaining the connection (called when app is closed)
  Future<void> shutdown() async {
    // No-op
  }

  /// Manually connect to the device
  Future<void> connect({String? remoteId}) async {
    try {
      debugPrint('Attempting to connect to Bluetooth device...');
      await _deviceService.connect(remoteId: remoteId);
    } catch (e) {
      debugPrint('Connection failed: $e');
      rethrow;
    }
  }

  /// Manually disconnect from the device (keeps device saved)
  Future<void> disconnect() async {
    await _deviceService.disconnect(userInitiated: false);
  }

  // ponytail: fixed settle for the pod to drop the link and restart
  // advertising; tune after device testing.
  static const _podSettleAfterDisconnect = Duration(seconds: 5);

  /// Manually disconnect by user (user clicked Disconnect).
  /// Holds the same [AlignEyeDeviceService.isResetting] gate as Forget, so
  /// "Connect saved pod" stays blocked until the pod is really free. A
  /// reconnect a few seconds after cutting the pod off mid FETCH_SESSIONS
  /// hangs the pod on the MTU exchange (status 133, "setup didn't finish").
  Future<void> disconnectByUser() async {
    final resetting = _deviceService.isResetting;
    if (resetting.value) return;
    resetting.value = true;
    try {
      await BleSessionSync.waitForIdle();
      await _deviceService.disconnect(userInitiated: true);
      await Future.delayed(_podSettleAfterDisconnect);
    } finally {
      resetting.value = false;
    }
  }

  /// Forget the device completely (user clicked Forget Device)
  Future<void> forgetDevice() async {
    await _deviceService.forgetDevice();
  }
}
