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
}
