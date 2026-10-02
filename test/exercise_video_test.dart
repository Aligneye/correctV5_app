import 'package:flutter_test/flutter_test.dart';
import 'package:correctv1/services/exercise_video_service.dart';

void main() {
  test('fromJson fills defaults for missing fields', () {
    final v = ExerciseVideo.fromJson({'id': 'a', 'video_path': 'neck.mp4'});
    expect(v.title, '');
    expect(v.category, '');
    expect(v.durationSec, 0);
    expect(v.thumbPath, isNull);
  });

  test('toJson round-trips for offline cache', () {
    final v = ExerciseVideo.fromJson({
      'id': 'b',
      'title': 'Chin tuck',
      'category': 'Neck',
      'duration_sec': 95.0,
      'video_path': 'chin.mp4',
      'thumb_path': 'chin.jpg',
    });
    final r = ExerciseVideo.fromJson(v.toJson());
    expect(r.title, 'Chin tuck');
    expect(r.durationSec, 95);
    expect(r.thumbPath, 'chin.jpg');
  });
}
