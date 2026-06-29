import 'package:flutter_test/flutter_test.dart';
import 'package:correctv1/bluetooth/aligneye_device_service.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';

void main() {
  group('BLE Telemetry Parser Tests', () {
    test('Parse TP (Therapy Plan) packet', () {
      final json = <String, dynamic>{
        't': 'TP',
        'sid': 3,
        'duration': 1200,
        'pattern_dur': 120,
        'total': 10,
        'intensity': 2,
        'seq': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
      };

      final reading = PostureReading.fromJson(json);

      expect(reading.mode, equals('THERAPY'));
      expect(reading.liveSessionId, equals(3));
      expect(reading.therapyRemainingSeconds, equals(1200));
      expect(reading.therapyTotalDurationSeconds, equals(1200));
      // Wait, let's look at therapyPatternRemainingSeconds on TP: it is json['p_remaining'] ?? (json['t'] == 'TP' ? json['pattern_dur'] : null). So it is pattern_dur (120).
      expect(reading.therapyPatternRemainingSeconds, equals(120));
      expect(reading.therapyPatternDurationSeconds, equals(120));
      expect(reading.therapyTotalPatterns, equals(10));
      expect(reading.therapyIntensityLevel, equals(2));
      expect(reading.therapyPatternSequence, equals([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]));
    });

    test('Parse TL (Therapy Live Progress) packet', () {
      final json = <String, dynamic>{
        't': 'TL',
        'sid': 3,
        'idx': 1,
        'pid': 0,
        'intensity': 2,
        'elapsed': 5,
        'remaining': 1195,
        'p_elapsed': 10,
        'p_remaining': 110,
        'angle': 35.0,
        'posture': 'BAD POSTURE',
      };

      final reading = PostureReading.fromJson(json);

      expect(reading.liveSessionId, equals(3));
      expect(reading.therapyCurrentPatternIndex, equals(0)); // 1-based idx: 1 -> 0
      expect(reading.therapyPatternId, equals(0)); // pid: 0
      expect(reading.therapyPattern, equals('Muscle Act')); // pid: 0 translates to Muscle Act
      expect(reading.therapyIntensityLevel, equals(2));
      expect(reading.therapyElapsedSeconds, equals(5));
      expect(reading.therapyRemainingSeconds, equals(1195));
      expect(reading.therapyTotalDurationSeconds, equals(1200)); // elapsed (5) + remaining (1195)
      expect(reading.therapyPatternElapsedSeconds, equals(10));
      expect(reading.therapyPatternRemainingSeconds, equals(110));
      expect(reading.therapyPatternDurationSeconds, equals(120)); // p_elapsed (10) + p_remaining (110)
      expect(reading.angle, equals(35.0));
      expect(reading.posture, equals('BAD POSTURE'));
      expect(reading.isBadPosture, isTrue);
    });

    test('Friendly and firmware name resolution', () {
      expect(firmwarePatternName(0), equals('Muscle Act'));
      expect(therapyPatternName(0), equals('Wake-Up Pulse'));
      expect(friendlyTherapyPatternLabel('Muscle Act'), equals('Wake-Up Pulse'));
    });
  });
}
