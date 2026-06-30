import 'package:flutter/foundation.dart';
import 'package:nordic_dfu/nordic_dfu.dart';

class DfuUpdateService {
  Future<void> startDfu({
    required String deviceAddress,
    required String firmwareZipPath,
    required void Function(int percent) onProgress,
    required void Function() onCompleted,
    required void Function(String message) onError,
  }) async {
    try {
      await NordicDfu().startDfu(
        deviceAddress,
        firmwareZipPath,
        fileInAsset: false,
        numberOfPackets: 6,
        androidParameters: const AndroidParameters(
          packetReceiptNotificationsEnabled: true,
        ),
        dfuEventHandler: DfuEventHandler(
          onProgressChanged: (
            address,
            percent,
            speed,
            avgSpeed,
            currentPart,
            partsTotal,
          ) {
            onProgress(percent);
          },
          onDfuCompleted: (address) {
            debugPrint('DFU completed on $address');
            onCompleted();
          },
          onError: (address, error, errorType, message) {
            debugPrint('DFU error on $address: $message (type=$errorType)');
            onError(message);
          },
        ),
      );
    } catch (e) {
      debugPrint('DFU exception: $e');
      onError(e.toString());
    }
  }
}
