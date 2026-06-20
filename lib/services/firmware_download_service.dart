import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class FirmwareDownloadService {
  /// Downloads the firmware ZIP from [url] into the app cache directory.
  /// Reports download progress via [onProgress] (0.0 – 1.0).
  /// Throws if the download fails or the file is empty.
  /// Returns the local file path on success.
  Future<String> download(
    String url, {
    void Function(double)? onProgress,
  }) async {
    final cacheDir = await getTemporaryDirectory();
    final fileName = url.split('/').last.split('?').first;
    final file = File('${cacheDir.path}/$fileName');

    // Delete a previous incomplete download.
    if (await file.exists()) await file.delete();

    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send().timeout(const Duration(minutes: 5));

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    int received = 0;
    final sink = file.openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (totalBytes > 0) {
        onProgress?.call(received / totalBytes);
      }
    }
    await sink.close();

    if (!(await file.exists()) || (await file.length()) == 0) {
      throw Exception('Downloaded file is empty');
    }

    debugPrint('Firmware downloaded: ${file.path} ($received bytes)');
    return file.path;
  }

  /// Verifies the SHA256 hash of [filePath] against [expectedHash].
  /// Deletes the file and throws if the hash does not match.
  Future<void> verifySha256(String filePath, String expectedHash) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();

    if (digest.toLowerCase() != expectedHash.toLowerCase()) {
      await file.delete();
      throw Exception(
        'Firmware verification failed: hash mismatch.\n'
        'Expected: $expectedHash\n'
        'Got:      $digest',
      );
    }
    debugPrint('Firmware SHA256 verified: $digest');
  }

  Future<void> deleteIfExists(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }
}
