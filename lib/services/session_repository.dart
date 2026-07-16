import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:correctv1/analytics/analytics_screen.dart';
import 'package:correctv1/services/session_database.dart';
import 'package:correctv1/services/therapy_pattern_names.dart';

/// Thin read layer over the local `sessions` SQLite table.
///
/// All queries are scoped to the current `auth.uid()`. The local database is
/// the source of truth for reads; background sync pushes data to Supabase.
class SessionRepository {
  SessionRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Convenience: this week only (Monday 00:00 local -> now).
  Future<List<SessionData>> fetchThisWeek({String? liveSessionId}) =>
      fetchByPeriod('week', liveSessionId: liveSessionId);

  /// Load a single session by local db id (what LiveSessionRecorder exposes
  /// via `DeviceManager.activeSessionId`). Returns null when the row isn't
  /// present locally (e.g. the recorder dropped it for being too short).
  Future<SessionData?> fetchById(String id) async {
    final row = await SessionDatabase.instance.getById(id);
    if (row == null) return null;
    return _rowToSession(row, 0);
  }

  /// period ∈ {'week', 'month', 'all'}.
  /// Unknown periods fall back to 'all' so the UI never breaks on a typo.
  Future<List<SessionData>> fetchByPeriod(
      String period, {
        String? liveSessionId,
      }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    await _ensureCacheWarmed(userId);

    final since = _periodStart(period);
    final rows = await SessionDatabase.instance.fetchByUser(
      userId,
      since: since,
    );
    return _mapRows(rows, liveSessionId: liveSessionId);
  }

  /// Summary stats for the current week.
  Future<Map<String, dynamic>> fetchWeeklyStats() async {
    final now = DateTime.now();
    final thisWeekStart = _startOfWeek(now);
    final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

    final thisWeekRows = await _fetchRowsBetween(thisWeekStart, now);
    final lastWeekRows = await _fetchRowsBetween(lastWeekStart, thisWeekStart);

    final thisWeek = _aggregate(thisWeekRows);
    final lastWeek = _aggregate(lastWeekRows);

    final trackedDelta =
        thisWeek.trackedHoursNumeric - lastWeek.trackedHoursNumeric;

    return {
      'goodPosturePct': thisWeek.goodPosturePct,
      'trackedHours': thisWeek.trackedHours,
      'sessionCount': thisWeek.sessionCount,
      'therapyMinutes': thisWeek.therapyMinutes,
      'deltaVsLastWeek': {
        'goodPosturePct': thisWeek.goodPosturePct - lastWeek.goodPosturePct,
        'trackedHours': double.parse(trackedDelta.toStringAsFixed(1)),
        'sessionCount': thisWeek.sessionCount - lastWeek.sessionCount,
        'therapyMinutes': thisWeek.therapyMinutes - lastWeek.therapyMinutes,
      },
    };
  }

  /// Today-vs-yesterday summary driven by local `sessions` rows (Supabase
  /// mirrors them). No separate daily-score table needed.
  Future<TodayStats> fetchTodayStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final todayRows = await _fetchRowsBetween(todayStart, tomorrowStart);
    final yesterdayRows = await _fetchRowsBetween(yesterdayStart, todayStart);

    final today = _summarizeDay(todayRows);
    final yesterday = _summarizeDay(yesterdayRows);

    return TodayStats(
      todayPct: today.postureDurationSec > 0 ? today.posturePct : 0,
      todayPostureDurationSec: today.postureDurationSec,
      todayTherapyDurationSec: today.therapyDurationSec,
      todaySessionCount: today.sessionCount,
      todayTrackedSec: today.trackedSec,
      yesterdayPct: yesterday.postureDurationSec > 0
          ? yesterday.posturePct
          : 0,
      yesterdayHasPostureData: yesterday.postureDurationSec > 0,
      yesterdayPostureDurationSec: yesterday.postureDurationSec,
      yesterdayTherapyDurationSec: yesterday.therapyDurationSec,
      yesterdaySessionCount: yesterday.sessionCount,
      yesterdayTrackedSec: yesterday.trackedSec,
      yesterdayHasTrackedData: yesterday.trackedSec > 0,
    );
  }

  _DaySummary _summarizeDay(List<Map<String, dynamic>> rows) {
    int postureDur = 0;
    int postureWrong = 0;
    int therapyDur = 0;
    int trackedSec = 0;
    int sessionCount = 0;
    for (final row in rows) {
      final dur = _asInt(row['duration_sec']);
      if (dur <= 0) continue;
      sessionCount++;
      trackedSec += dur;
      final type = row['type']?.toString();
      if (type == 'posture') {
        postureDur += dur;
        postureWrong += _asInt(row['wrong_dur_sec']);
      } else if (type == 'therapy') {
        therapyDur += dur;
      }
    }
    final pct = postureDur > 0
        ? (100 - (postureWrong / postureDur * 100)).round().clamp(0, 100)
        : 0;
    return _DaySummary(
      posturePct: pct,
      postureDurationSec: postureDur,
      therapyDurationSec: therapyDur,
      trackedSec: trackedSec,
      sessionCount: sessionCount,
    );
  }

  /// Current streak with freeze-token support.
  ///
  /// Returns [StreakStats] with freeze fields populated from Supabase
  /// (or safe defaults on network failure).
  Future<StreakStats> fetchStreakStats() async {
    final now = DateTime.now();
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 400));
    final rows = await _fetchRowsBetween(
      windowStart,
      now.add(const Duration(days: 1)),
    );

    final activeDays = <DateTime>{};
    for (final row in rows) {
      final dur = _asInt(row['duration_sec']);
      if (dur <= 0) continue;
      final ts = _parseTs(row['start_ts'])?.toLocal();
      if (ts == null) continue;
      activeDays.add(_streakDayOf(ts));
    }

    final todayStreakDay = _streakDayOf(now);
    final todayActive = activeDays.contains(todayStreakDay);

    // Fetch freeze tokens from Supabase.
    int freezeTokens = 2;
    List<DateTime> freezeUsedDays = [];
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        final existing = await _client
            .from('user_streaks')
            .select('freeze_tokens, freeze_used_days')
            .eq('user_id', userId)
            .maybeSingle();
        if (existing != null) {
          freezeTokens = (existing['freeze_tokens'] as num?)?.toInt() ?? 2;
          final rawDays = existing['freeze_used_days'];
          if (rawDays is List) {
            for (final d in rawDays) {
              final parsed = DateTime.tryParse(d?.toString() ?? '');
              if (parsed != null) freezeUsedDays.add(parsed);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('SessionRepository: fetchStreakStats freeze fetch failed: $e');
    }

    final frozenDays = <DateTime>{};
    final cutoff = todayStreakDay.subtract(const Duration(days: 30));

    DateTime cursor = todayActive
        ? todayStreakDay
        : todayStreakDay.subtract(const Duration(days: 1));
    int streak = 0;
    int tokensRemaining = freezeTokens;

    while (true) {
      if (activeDays.contains(cursor) || frozenDays.contains(cursor)) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      // Missing day — try freeze
      final alreadyFrozen = freezeUsedDays.any(
            (d) =>
        d.year == cursor.year &&
            d.month == cursor.month &&
            d.day == cursor.day,
      );
      if (!alreadyFrozen &&
          tokensRemaining > 0 &&
          cursor.isAfter(cutoff)) {
        frozenDays.add(cursor);
        tokensRemaining--;
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      break;
    }

    final newFreezeUsedDays = [...freezeUsedDays, ...frozenDays];

    // Replenish +1 token at every 7-day milestone, cap at 5.
    int newFreezeTokens = tokensRemaining;
    if (streak > 0 && streak % 7 == 0) {
      newFreezeTokens = (newFreezeTokens + 1).clamp(0, 5);
    }

    final highestStreak = await _syncStreakToSupabase(
      currentStreak: streak,
      todayStreakDay: todayStreakDay,
      freezeTokens: newFreezeTokens,
      freezeUsedDays: newFreezeUsedDays,
    );

    return StreakStats(
      currentStreak: streak,
      highestStreak: highestStreak,
      todayActive: todayActive,
      todayStreakDay: todayStreakDay,
      freezeTokens: newFreezeTokens,
      freezeUsedDays: newFreezeUsedDays,
    );
  }

  /// Upserts the user's current streak into `user_streaks`, bumping
  /// `highest_streak` when the current run exceeds it. Returns the stored
  /// highest (or local fallback on network failure).
  Future<int> _syncStreakToSupabase({
    required int currentStreak,
    required DateTime todayStreakDay,
    int freezeTokens = 2,
    List<DateTime> freezeUsedDays = const [],
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return currentStreak;

    try {
      final existing = await _client
          .from('user_streaks')
          .select('highest_streak')
          .eq('user_id', userId)
          .maybeSingle();

      final previousHighest =
          (existing?['highest_streak'] as num?)?.toInt() ?? 0;
      final newHighest = currentStreak > previousHighest
          ? currentStreak
          : previousHighest;

      final freezeDayStrings = freezeUsedDays
          .map(
            (d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      )
          .toList();

      await _client.from('user_streaks').upsert({
        'user_id': userId,
        'current_streak': currentStreak,
        'highest_streak': newHighest,
        'last_active_day':
        '${todayStreakDay.year.toString().padLeft(4, '0')}-${todayStreakDay.month.toString().padLeft(2, '0')}-${todayStreakDay.day.toString().padLeft(2, '0')}',
        'freeze_tokens': freezeTokens,
        'freeze_used_days': freezeDayStrings,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      return newHighest;
    } catch (e) {
      debugPrint('SessionRepository: _syncStreakToSupabase failed: $e');
      return currentStreak;
    }
  }

  /// Normalizes a local timestamp to its "streak day" (the calendar date at
  /// 6 AM local). Anything before 6 AM rolls back to the prior date.
  DateTime _streakDayOf(DateTime localTs) {
    final shifted = localTs.subtract(const Duration(hours: 6));
    return DateTime(shifted.year, shifted.month, shifted.day);
  }

  // ── XP System ──────────────────────────────────────────────────────────────
  //
  // Dual-pool leveling:
  //  - Every level needs [kXpPerLevel] (600) XP total, split into two pools:
  //    [kPoolXpPerLevel] (300) from Therapy + 300 from Training.
  //  - Both modes earn [kXpPerMinute] (10) XP per minute, min 5 XP/session.
  //  - Level up ONLY when BOTH pools are full. Extra XP earned in one pool
  //    carries forward into that same pool for the next level.

  static const int kXpPerMinute = 10;
  static const int kPoolXpPerLevel = 300;
  static const int kXpPerLevel = kPoolXpPerLevel * 2; // 600

  /// Total XP required to *reach* [level] (level 1 => 0).
  static int _xpForLevel(int level) => (level - 1) * kXpPerLevel;

  /// XP for a single session at 10 XP/min, minimum 5 XP.
  static int xpForDuration(int durationSec) {
    if (durationSec <= 0) return 0;
    final xp = (durationSec ~/ 60) * kXpPerMinute;
    return xp < 5 ? 5 : xp;
  }

  Future<XpStats> fetchXpStats() async {
    final now = DateTime.now();
    final windowStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 400));
    final rows = await _fetchRowsBetween(
      windowStart,
      now.add(const Duration(days: 1)),
    );

    int therapyXpTotal = 0;
    int trainingXpTotal = 0;
    for (final row in rows) {
      final dur = _asInt(row['duration_sec']);
      if (dur <= 0) continue;
      final xp = xpForDuration(dur);
      final type = row['type']?.toString() ?? '';
      if (type == 'therapy') {
        therapyXpTotal += xp;
      } else {
        trainingXpTotal += xp;
      }
    }

    final totalXp = therapyXpTotal + trainingXpTotal;

    // Level up only when BOTH pools have banked 300 XP each.
    final therapyLevelsDone = therapyXpTotal ~/ kPoolXpPerLevel;
    final trainingLevelsDone = trainingXpTotal ~/ kPoolXpPerLevel;
    final completedLevels = therapyLevelsDone < trainingLevelsDone
        ? therapyLevelsDone
        : trainingLevelsDone;
    final level = 1 + completedLevels;

    // Progress inside the current level, clamped to the pool cap so an
    // over-earned pool shows as "full" while the other catches up.
    final therapyLevelXp = (therapyXpTotal - completedLevels * kPoolXpPerLevel)
        .clamp(0, kPoolXpPerLevel)
        .toInt();
    final trainingLevelXp =
    (trainingXpTotal - completedLevels * kPoolXpPerLevel)
        .clamp(0, kPoolXpPerLevel)
        .toInt();

    await _syncXpToSupabase(totalXp: totalXp, level: level);

    return XpStats(
      totalXp: totalXp,
      currentLevel: level,
      xpForCurrentLevel: _xpForLevel(level),
      xpForNextLevel: _xpForLevel(level + 1),
      therapyLevelXp: therapyLevelXp,
      trainingLevelXp: trainingLevelXp,
    );
  }

  Future<void> _syncXpToSupabase({
    required int totalXp,
    required int level,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('user_xp').upsert({
        'user_id': userId,
        'total_xp': totalXp,
        'current_level': level,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');
    } catch (e) {
      debugPrint('SessionRepository: _syncXpToSupabase failed: $e');
    }
  }

  // ── Streak Calendar ────────────────────────────────────────────────────────

  /// Returns day-states for the last [days] streak-days (oldest first).
  /// 0 = inactive, 1 = active, 2 = freeze-used.
  Future<List<int>> fetchStreakCalendar(
      int days, {
        List<DateTime> freezeUsedDays = const [],
      }) async {
    final now = DateTime.now();
    final todayStreakDay = _streakDayOf(now);
    final windowStart = todayStreakDay.subtract(Duration(days: days - 1));

    final rows = await _fetchRowsBetween(
      windowStart.subtract(const Duration(hours: 6)),
      now.add(const Duration(days: 1)),
    );

    final activeDays = <DateTime>{};
    for (final row in rows) {
      final dur = _asInt(row['duration_sec']);
      if (dur <= 0) continue;
      final ts = _parseTs(row['start_ts'])?.toLocal();
      if (ts == null) continue;
      activeDays.add(_streakDayOf(ts));
    }

    return List<int>.generate(days, (i) {
      final day = windowStart.add(Duration(days: i));
      if (activeDays.contains(day)) return 1;
      final frozen = freezeUsedDays.any(
            (d) =>
        d.year == day.year && d.month == day.month && d.day == day.day,
      );
      if (frozen) return 2;
      return 0;
    });
  }

  // ── Weekly Recap ───────────────────────────────────────────────────────────

  Future<WeeklyRecap> fetchWeeklyRecap() async {
    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final rows = await _fetchRowsBetween(weekStart, weekEnd);
    final activeDaySet = <DateTime>{};
    int weekXp = 0;

    for (final row in rows) {
      final dur = _asInt(row['duration_sec']);
      if (dur <= 0) continue;
      final ts = _parseTs(row['start_ts'])?.toLocal();
      if (ts != null) {
        activeDaySet.add(DateTime(ts.year, ts.month, ts.day));
      }
      weekXp += xpForDuration(dur);
    }

    return WeeklyRecap(
      activeDays: activeDaySet.length,
      totalDays: 7,
      totalXpThisWeek: weekXp,
      weekStartDate: weekStart,
    );
  }

  // ── Daily good-posture % ───────────────────────────────────────────────────

  /// Daily good-posture % for the last [days] calendar days (oldest first).
  Future<List<double>> fetchDailyScores(int days) async {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));

    final rows = await _fetchRowsBetween(start, now, typeFilter: 'posture');

    final dailyDur = List<int>.filled(days, 0);
    final dailyWrong = List<int>.filled(days, 0);

    for (final row in rows) {
      final ts = _parseTs(row['start_ts']);
      if (ts == null) continue;
      final local = ts.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      final idx = day
          .difference(DateTime(start.year, start.month, start.day))
          .inDays;
      if (idx < 0 || idx >= days) continue;
      dailyDur[idx] += _asInt(row['duration_sec']);
      dailyWrong[idx] += _asInt(row['wrong_dur_sec']);
    }

    return List<double>.generate(days, (i) {
      final dur = dailyDur[i];
      if (dur <= 0) return 0;
      final pct = (100 - (dailyWrong[i] / dur * 100)).clamp(0, 100);
      return pct.toDouble();
    });
  }

  Future<List<int>> fetchHeatmapData() async {
    const days = 28;

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: days - 1));

    final rows = await _fetchRowsBetween(start, now.add(const Duration(days: 1)));

    final dailyMinutes = List<int>.filled(days, 0);

    for (final row in rows) {
      final ts = _parseTs(row['start_ts']);
      if (ts == null) continue;

      final local = ts.toLocal();
      final day = DateTime(local.year, local.month, local.day);

      final idx = day
          .difference(DateTime(start.year, start.month, start.day))
          .inDays;

      if (idx < 0 || idx >= days) continue;

      dailyMinutes[idx] += (_asInt(row['duration_sec']) ~/ 60);
    }

    return dailyMinutes.map((minutes) {
      if (minutes == 0) return 0;
      if (minutes < 15) return 1;
      if (minutes < 30) return 2;
      if (minutes < 60) return 3;
      return 4;
    }).toList();
  }

  // ── internals ──────────────────────────────────────────────────────────────

  bool _cacheWarmed = false;

  Future<void> _ensureCacheWarmed(String userId) async {
    if (_cacheWarmed) return;
    _cacheWarmed = true;

    final hasLocal = await SessionDatabase.instance.hasDataForUser(userId);
    if (hasLocal) return;

    // First time: pull existing sessions from Supabase into local cache.
    try {
      final rows = await _client
          .from('sessions')
          .select()
          .order('start_ts', ascending: false);
      for (final row in (rows as List<dynamic>)) {
        await SessionDatabase.instance.upsertFromRemote(
          row as Map<String, dynamic>,
        );
      }
      debugPrint('SessionRepository: cache warmed with ${rows.length} rows');
    } catch (e) {
      debugPrint('SessionRepository: cache warm failed (offline?): $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRowsBetween(
      DateTime startInclusive,
      DateTime endExclusive, {
        String? typeFilter,
      }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    await _ensureCacheWarmed(userId);

    return SessionDatabase.instance.fetchBetween(
      userId,
      startInclusive,
      endExclusive,
      typeFilter: typeFilter,
    );
  }

  DateTime? _periodStart(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'week':
        return _startOfWeek(now);
      case 'month':
        return DateTime(now.year, now.month, 1);
      case 'all':
      default:
        return null;
    }
  }

  DateTime _startOfWeek(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  List<SessionData> _mapRows(List<dynamic> rows, {String? liveSessionId}) {
    final out = <SessionData>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i] as Map<String, dynamic>;
      final mapped = _rowToSession(row, i, liveSessionId: liveSessionId);
      if (mapped != null) out.add(mapped);
    }
    return out;
  }

  SessionData? _rowToSession(
      Map<String, dynamic> row,
      int index, {
        String? liveSessionId,
      }) {
    final typeStr = row['type']?.toString() ?? '';
    final isPosture = typeStr == 'posture';
    final type = isPosture ? SessionType.posture : SessionType.therapy;

    final durationSec = _asInt(row['duration_sec']);
    if (durationSec < 0) return null;

    final startTs = _parseTs(row['start_ts'])?.toLocal();
    if (startTs == null && durationSec == 0) return null;
    final wrongDurSec = isPosture ? _asInt(row['wrong_dur_sec']) : null;

    final score = isPosture ? _scoreFrom(durationSec, wrongDurSec ?? 0) : null;

    final pattern = isPosture ? null : _asIntOrNull(row['therapy_pattern']);
    final alerts = isPosture ? _asIntOrNull(row['wrong_count']) : null;
    final dbId = (row['remote_id'] ?? row['id'])?.toString();
    final tsSynced = row['ts_synced'] == true || row['ts_synced'] == 1;
    final syncStatus = row['sync_status'];
    final cloudSynced = syncStatus == 1;

    final postureEvents = isPosture
        ? _parsePostureEvents(row['posture_events'])
        : null;
    final therapyPatterns = isPosture
        ? null
        : _parseTherapyPatterns(row['therapy_patterns']);
    final therapyPatternEvents = isPosture
        ? null
        : _parseTherapyPatternEvents(
      row['therapy_pattern_events'],
      therapyPatterns,
      pattern,
      durationSec,
    );

    return SessionData(
      id: index,
      dbId: dbId,
      type: type,
      name: isPosture ? 'Posture training' : 'Vibration therapy',
      time: _formatRelativeTime(startTs),
      date: _formatShortDate(startTs),
      duration: _formatDuration(durationSec),
      durationSec: durationSec,
      alerts: alerts,
      score: score,
      pattern: pattern,
      wrongDurSec: wrongDurSec,
      isLive: dbId != null && dbId == liveSessionId,
      tsSynced: tsSynced,
      cloudSynced: cloudSynced,
      startTs: startTs,
      postureEvents: postureEvents,
      therapyPatterns: therapyPatterns,
      therapyPatternEvents: therapyPatternEvents,
    );
  }

  List<PostureEvent>? _parsePostureEvents(dynamic raw) {
    if (raw is! List) return null;
    final out = <PostureEvent>[];
    for (final entry in raw) {
      if (entry is Map) {
        out.add(PostureEvent.fromJson(entry.cast<String, dynamic>()));
      }
    }
    return out.isEmpty ? null : out;
  }

  List<int>? _parseTherapyPatterns(dynamic raw) {
    if (raw is! List) return null;
    final out = <int>[];
    for (final entry in raw) {
      if (entry is num) {
        out.add(entry.toInt());
      } else {
        final parsed = int.tryParse(entry?.toString() ?? '');
        if (parsed != null) out.add(parsed);
      }
    }
    if (out.isEmpty) return null;
    return _normalizeTherapyPatterns(out);
  }

  List<TherapyPatternEvent>? _parseTherapyPatternEvents(
      dynamic raw,
      List<int>? fallbackPatterns,
      int? singlePattern,
      int durationSec,
      ) {
    if (raw is List) {
      final out = <TherapyPatternEvent>[];
      for (final entry in raw) {
        if (entry is Map) {
          final event = TherapyPatternEvent.fromJson(
            entry.cast<String, dynamic>(),
          );
          if (event.patternIndex >= 0) out.add(event);
        }
      }
      if (out.isNotEmpty) {
        out.sort((a, b) => a.startOffsetSec.compareTo(b.startOffsetSec));
        final normalizedEvents = _playedTherapyPatternEvents(
          _normalizeTherapyPatternEvents(out),
          durationSec,
        );
        if (fallbackPatterns == null ||
            normalizedEvents.length >= fallbackPatterns.length) {
          return normalizedEvents;
        }
      }
    }

    final patterns =
        fallbackPatterns ??
            (singlePattern == null ? null : <int>[singlePattern]);
    if (patterns == null || patterns.isEmpty) return null;

    final safeDuration = durationSec.clamp(0, 1 << 30).toInt();
    if (safeDuration <= 0) {
      return [
        for (var i = 0; i < patterns.length; i++)
          TherapyPatternEvent(
            patternIndex: patterns[i],
            startOffsetSec: 0,
            durationSec: 0,
          ),
      ];
    }

    var cursor = 0;
    final events = <TherapyPatternEvent>[];
    for (var i = 0; i < patterns.length; i++) {
      final remaining = (safeDuration - cursor).clamp(0, 1 << 30).toInt();
      if (remaining <= 0) break;

      final dur = remaining.clamp(0, 60).toInt();
      events.add(
        TherapyPatternEvent(
          patternIndex: patterns[i],
          startOffsetSec: cursor,
          durationSec: dur,
        ),
      );
      cursor += dur;
    }
    return events.isEmpty ? null : events;
  }

  List<int> _normalizeTherapyPatterns(List<int> patterns) {
    final normalized = <int>[];
    for (final pattern in patterns) {
      final value = therapyPatternIndexFromDeviceNumber(pattern);
      if (value != null) normalized.add(value);
    }
    return normalized.isEmpty ? patterns : normalized;
  }

  List<TherapyPatternEvent> _normalizeTherapyPatternEvents(
      List<TherapyPatternEvent> events,
      ) {
    final normalized = <TherapyPatternEvent>[];
    for (final event in events) {
      final pattern = therapyPatternIndexFromDeviceNumber(event.patternIndex);
      if (pattern == null) continue;
      normalized.add(
        TherapyPatternEvent(
          patternIndex: pattern,
          startOffsetSec: event.startOffsetSec,
          durationSec: event.durationSec,
        ),
      );
    }
    return normalized.isEmpty ? events : normalized;
  }

  List<TherapyPatternEvent> _playedTherapyPatternEvents(
      List<TherapyPatternEvent> events,
      int durationSec,
      ) {
    final safeDuration = durationSec.clamp(0, 1 << 30).toInt();
    final played = <TherapyPatternEvent>[];
    for (final event in events) {
      if (event.durationSec <= 0 || event.startOffsetSec >= safeDuration) {
        continue;
      }
      final remaining = (safeDuration - event.startOffsetSec)
          .clamp(0, 1 << 30)
          .toInt();
      final duration = event.durationSec > remaining
          ? remaining
          : event.durationSec;
      if (duration <= 0) continue;
      played.add(
        TherapyPatternEvent(
          patternIndex: event.patternIndex,
          startOffsetSec: event.startOffsetSec,
          durationSec: duration,
        ),
      );
    }
    return played;
  }

  int _scoreFrom(int durationSec, int wrongDurSec) {
    if (durationSec <= 0) return 100;
    return (100 - (wrongDurSec / durationSec * 100)).round().clamp(0, 100);
  }

  _Aggregate _aggregate(List<Map<String, dynamic>> rows) {
    int totalPostureDur = 0;
    int totalWrongDur = 0;
    int therapyMinutes = 0;
    int trackedSec = 0;

    for (final row in rows) {
      final type = row['type']?.toString() ?? '';
      final dur = _asInt(row['duration_sec']);
      trackedSec += dur;
      if (type == 'posture') {
        totalPostureDur += dur;
        totalWrongDur += _asInt(row['wrong_dur_sec']);
      } else if (type == 'therapy') {
        therapyMinutes += (dur / 60).round();
      }
    }

    final pct = totalPostureDur > 0
        ? (100 - (totalWrongDur / totalPostureDur * 100)).round().clamp(0, 100)
        : 0;

    final trackedHoursNum = trackedSec / 3600.0;
    return _Aggregate(
      goodPosturePct: pct,
      trackedHours: trackedHoursNum.toStringAsFixed(1),
      trackedHoursNumeric: trackedHoursNum,
      sessionCount: rows.length,
      therapyMinutes: therapyMinutes,
    );
  }

  DateTime? _parseTs(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  int? _asIntOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _formatDuration(int durationSec) {
    if (durationSec <= 0) return '0s';
    if (durationSec < 60) return '${durationSec}s';
    final minutes = durationSec ~/ 60;
    final seconds = durationSec % 60;
    if (seconds == 0) return '$minutes min';
    return '$minutes min ${seconds}s';
  }

  String _formatShortDate(DateTime? ts) {
    if (ts == null) return '—';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[ts.month - 1]} ${ts.day}';
  }

  String _formatRelativeTime(DateTime? ts) {
    if (ts == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tsDay = DateTime(ts.year, ts.month, ts.day);
    final diffDays = today.difference(tsDay).inDays;

    final hour = ts.hour == 0 ? 12 : (ts.hour > 12 ? ts.hour - 12 : ts.hour);
    final minute = ts.minute.toString().padLeft(2, '0');
    final ampm = ts.hour >= 12 ? 'PM' : 'AM';
    final hhmm = '$hour:$minute $ampm';

    if (diffDays == 0) return 'Today · $hhmm';
    if (diffDays == 1) return 'Yesterday · $hhmm';
    return '${_formatShortDate(ts)} · $hhmm';
  }
}

// ── Data classes ───────────────────────────────────────────────────────────────

class XpStats {
  const XpStats({
    required this.totalXp,
    required this.currentLevel,
    required this.xpForCurrentLevel,
    required this.xpForNextLevel,
    this.therapyLevelXp = 0,
    this.trainingLevelXp = 0,
  });

  final int totalXp;
  final int currentLevel;
  final int xpForCurrentLevel;
  final int xpForNextLevel;

  /// XP banked toward the current level's Therapy pool (0..300).
  final int therapyLevelXp;

  /// XP banked toward the current level's Training pool (0..300).
  final int trainingLevelXp;

  int get xpProgress => therapyLevelXp + trainingLevelXp;
  int get xpNeeded => SessionRepository.kXpPerLevel;
  double get levelProgress =>
      xpNeeded <= 0 ? 1.0 : (xpProgress / xpNeeded).clamp(0.0, 1.0);

  double get therapyPoolProgress =>
      (therapyLevelXp / SessionRepository.kPoolXpPerLevel).clamp(0.0, 1.0);
  double get trainingPoolProgress =>
      (trainingLevelXp / SessionRepository.kPoolXpPerLevel).clamp(0.0, 1.0);

  bool get therapyPoolFull =>
      therapyLevelXp >= SessionRepository.kPoolXpPerLevel;
  bool get trainingPoolFull =>
      trainingLevelXp >= SessionRepository.kPoolXpPerLevel;
}

class WeeklyRecap {
  const WeeklyRecap({
    required this.activeDays,
    required this.totalDays,
    required this.totalXpThisWeek,
    required this.weekStartDate,
  });

  final int activeDays;
  final int totalDays;
  final int totalXpThisWeek;
  final DateTime weekStartDate;
}

class StreakStats {
  const StreakStats({
    required this.currentStreak,
    required this.highestStreak,
    required this.todayActive,
    required this.todayStreakDay,
    this.freezeTokens = 2,
    this.freezeUsedDays = const [],
  });

  final int currentStreak;
  final int highestStreak;
  final bool todayActive;
  final DateTime todayStreakDay;
  final int freezeTokens;
  final List<DateTime> freezeUsedDays;

  bool get isNewRecord =>
      currentStreak > 0 && currentStreak >= highestStreak;
}

class TodayStats {
  const TodayStats({
    required this.todayPct,
    required this.todayPostureDurationSec,
    required this.todayTherapyDurationSec,
    required this.todaySessionCount,
    required this.todayTrackedSec,
    required this.yesterdayPct,
    required this.yesterdayHasPostureData,
    required this.yesterdayPostureDurationSec,
    required this.yesterdayTherapyDurationSec,
    required this.yesterdaySessionCount,
    required this.yesterdayTrackedSec,
    required this.yesterdayHasTrackedData,
  });

  final int todayPct;
  final int todayPostureDurationSec;
  final int todayTherapyDurationSec;
  final int todaySessionCount;
  final int todayTrackedSec;
  final int yesterdayPct;
  final bool yesterdayHasPostureData;
  final int yesterdayPostureDurationSec;
  final int yesterdayTherapyDurationSec;
  final int yesterdaySessionCount;
  final int yesterdayTrackedSec;
  final bool yesterdayHasTrackedData;

  bool get hasTodayPostureData => todayPostureDurationSec > 0;
  bool get hasTodayTherapyData => todayTherapyDurationSec > 0;
  bool get hasTodayTrackedData => todayTrackedSec > 0;
  bool get hasTodaySessions => todaySessionCount > 0;
  bool get yesterdayHasTherapyData => yesterdayTherapyDurationSec > 0;
  bool get yesterdayHasSessions => yesterdaySessionCount > 0;
  int get postureDeltaVsYesterday => todayPct - yesterdayPct;
  int get trackedDeltaSecVsYesterday => todayTrackedSec - yesterdayTrackedSec;
  int get therapyDeltaSecVsYesterday =>
      todayTherapyDurationSec - yesterdayTherapyDurationSec;
  int get trainingDeltaSecVsYesterday =>
      todayPostureDurationSec - yesterdayPostureDurationSec;
  int get sessionCountDeltaVsYesterday =>
      todaySessionCount - yesterdaySessionCount;
}

class _DaySummary {
  const _DaySummary({
    required this.posturePct,
    required this.postureDurationSec,
    required this.therapyDurationSec,
    required this.trackedSec,
    required this.sessionCount,
  });
  final int posturePct;
  final int postureDurationSec;
  final int therapyDurationSec;
  final int trackedSec;
  final int sessionCount;
}

class _Aggregate {
  _Aggregate({
    required this.goodPosturePct,
    required this.trackedHours,
    required this.trackedHoursNumeric,
    required this.sessionCount,
    required this.therapyMinutes,
  });

  final int goodPosturePct;
  final String trackedHours;
  final double trackedHoursNumeric;
  final int sessionCount;
  final int therapyMinutes;
}