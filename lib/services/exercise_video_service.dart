import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExerciseVideo {
  final String id;
  final String title;
  final String description;
  final String category;
  final int durationSec;
  final String videoPath;
  final String? thumbPath;

  const ExerciseVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.durationSec,
    required this.videoPath,
    this.thumbPath,
  });

  factory ExerciseVideo.fromJson(Map<String, dynamic> json) {
    return ExerciseVideo(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      durationSec: (json['duration_sec'] as num?)?.toInt() ?? 0,
      videoPath: json['video_path']?.toString() ?? '',
      thumbPath: json['thumb_path']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'duration_sec': durationSec,
        'video_path': videoPath,
        'thumb_path': thumbPath,
      };
}

/// Lists exercise videos from Supabase and manages offline copies on disk.
class ExerciseVideoService {
  ExerciseVideoService._();
  static final ExerciseVideoService instance = ExerciseVideoService._();

  static const _bucket = 'exercise-videos';
  static const _cacheKey = 'exercise_videos_cache';

  String publicUrl(String path) =>
      Supabase.instance.client.storage.from(_bucket).getPublicUrl(path);

  /// Fetches the catalogue; falls back to the last cached list when offline.
  Future<List<ExerciseVideo>> fetchVideos() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rows = await Supabase.instance.client
          .from('exercise_videos')
          .select()
          .eq('active', true)
          .order('sort_order');
      await prefs.setString(_cacheKey, jsonEncode(rows));
      return rows.map(ExerciseVideo.fromJson).toList();
    } catch (e) {
      debugPrint('Exercise videos fetch failed, using cache: $e');
      final cached = prefs.getString(_cacheKey);
      if (cached == null) rethrow;
      return (jsonDecode(cached) as List)
          .map((e) => ExerciseVideo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<File> _fileFor(ExerciseVideo v) async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/exercise_videos',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/${v.id}.mp4');
  }

  Future<String?> localPath(ExerciseVideo v) async {
    final file = await _fileFor(v);
    return await file.exists() ? file.path : null;
  }

  /// Streams the video to a `.part` file and renames it when complete, so a
  /// cancelled download never looks finished.
  Future<String> download(
    ExerciseVideo v, {
    void Function(double)? onProgress,
  }) async {
    final file = await _fileFor(v);
    final part = File('${file.path}.part');
    if (await part.exists()) await part.delete();

    final response = await http.Request('GET', Uri.parse(publicUrl(v.videoPath)))
        .send()
        .timeout(const Duration(minutes: 2));
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }
    if (received == 0) {
      await part.delete();
      throw Exception('Downloaded file is empty');
    }
    return (await part.rename(file.path)).path;
  }

  Future<void> delete(ExerciseVideo v) async {
    final file = await _fileFor(v);
    if (await file.exists()) await file.delete();
  }
}
