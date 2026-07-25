import 'dart:async';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
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

  /// Manually disconnect by user (user clicked Disconnect)
  Future<void> disconnectByUser() async {
    await _deviceService.disconnect(userInitiated: true);
  }

  /// Forget the device completely (user clicked Forget Device)
  Future<void> forgetDevice() async {
    await _deviceService.forgetDevice();
  }

  /// Called on app resume — silently reconnects if user had a device before
  /// and didn't intentionally disconnect. Checks BLE readiness first.
  Future<void> tryAutoReconnectOnResume() async {
    // Already connected or connecting — nothing to do
    final status = _deviceService.connectionStatus.value;
    if (status == DeviceConnectionStatus.connected ||
        status == DeviceConnectionStatus.connecting) return;

    // User intentionally disconnected — respect their choice
    if (_deviceService.userInitiatedDisconnect) return;

    // First time user — no device to reconnect to
    final everConnected = await _deviceService.hasEverConnected;
    if (!everConnected) return;

    // Check BLE readiness — permissions + BT on
    final readiness = await _deviceService.checkReadiness();
    if (readiness != BleReadiness.ready) {
      debugPrint(
        'Auto-reconnect on resume skipped: BLE not ready ($readiness)',
      );
      return;
    }

    debugPrint('App resumed — attempting silent auto-reconnect');
    try {
      await _deviceService.connect();
    } catch (e) {
      debugPrint('Auto-reconnect on resume failed (silent): $e');
    }
  }
}
