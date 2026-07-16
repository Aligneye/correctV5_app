import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:correctv1/services/session_database.dart';
import 'package:correctv1/services/session_sync_service.dart';

/// Progress snapshot emitted by [BleSessionSync.progress] for UI feedback.
class SyncProgress {
  const SyncProgress({
    required this.sent,
    required this.total,
    required this.complete,
    this.error,
  });

  final int sent;
  final int total;
  final bool complete;
  final Object? error;
}

/// Holds the data for one session received from firmware, ready to be
/// persisted to the local database.
class _SessionRecord {
  _SessionRecord({
    required this.q,
    required this.type,
    required this.startTsEpoch,
    required this.durationSec,
    required this.wrongCount,
    required this.wrongDurSec,
    required this.tsSynced,
    this.therapyPattern,
  });

  final int q; // packet index within this transfer
  final String type; // 'posture' or 'therapy'
  final int startTsEpoch; // unix epoch seconds (0 if unsynced)
  final int durationSec;
  final int wrongCount;
  final int wrongDurSec;
  final bool tsSynced;
  final int? therapyPattern;

  String? get startTsIso => startTsEpoch > 0
      ? DateTime.fromMillisecondsSinceEpoch(
          startTsEpoch * 1000,
          isUtc: true,
        ).toIso8601String()
      : null;
}

/// Pulls unsent posture/therapy sessions off the Align wearable using the
/// JSON-over-GATT protocol described in app_sync_proto §5.
///
/// Protocol summary:
///   App → Device : {"cmd":"FETCH_SESSIONS"}
///   Device → App : {"t":"SESS_HDR","n":N,"xfer":X}  (N=0 means drained)
///   Device → App : {"t":"SESS_DATA","q":Q,"ty":TY,"ts":TS,"d":D,"wc":WC,"wd":WD,...}
///   Device → App : {"t":"SESS_END","pk":PK,"xfer":X}
///   App → Device : {"cmd":"ACK_SESSIONS","ok":true,"xfer":X}          (all ok)
///                  {"cmd":"ACK_SESSIONS","nack":[…],"xfer":X}          (retry)
///
/// Uses the same GATT characteristic / notification stream already used for
/// posture telemetry, calibration, and profile commands.
class BleSessionSync {
  BleSessionSync(this._device, {SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final BluetoothDevice _device;
  final SupabaseClient _supabase;

  final _progressController = StreamController<SyncProgress>.broadcast();

  BluetoothCharacteristic? _char;
  StreamSubscription<List<int>>? _rawSub;

  int _sentCount = 0;
  bool _complete = false;
  bool _running = false;

  // Raw buffer for JSON framing (same framing as AlignEyeDeviceService).
  String _buf = '';

  // Completer used to await the next matching packet from firmware.
  Completer<Map<String, dynamic>>? _waitCompleter;
  bool Function(Map<String, dynamic>)? _waitMatcher;

  Stream<SyncProgress> get progress => _progressController.stream;

  Future<void> startSync() async {
    if (_running) {
      debugPrint('BleSessionSync: startSync() called while already running');
      return;
    }
    _running = true;
    _complete = false;
    _sentCount = 0;
    _buf = '';
    debugPrint('[SESSION] ── Sync started ── device=${_device.remoteId}');

    try {
      _char = _findChar();
      if (_char == null) {
        debugPrint(
          '[SESSION] ⚠️ No JSON characteristic found — firmware may be old',
        );
        _emitComplete();
        return;
      }

      _rawSub = _char!.onValueReceived.listen(
        _onRawBytes,
        onError: (Object e) {
          debugPrint('BleSessionSync: notify error: $e');
          _emitError(e);
        },
      );

      await _runFetchLoop();
    } catch (e) {
      debugPrint('BleSessionSync: fatal error: $e');
      _emitError(e);
    } finally {
      _emitComplete();
    }
  }

  Future<void> dispose() async {
    _waitCompleter?.complete(<String, dynamic>{});
    _waitCompleter = null;
    await _rawSub?.cancel();
    _rawSub = null;
    if (!_progressController.isClosed) {
      await _progressController.close();
    }
    _running = false;
  }

  // ── characteristic lookup ─────────────────────────────────────────────────

  static const String _kServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String _kCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  BluetoothCharacteristic? _findChar() {
    final services = _device.servicesList;
    for (final svc in services) {
      if (!_uuidMatch(svc.uuid, _kServiceUuid)) continue;
      for (final c in svc.characteristics) {
        if (_uuidMatch(c.uuid, _kCharUuid)) return c;
      }
    }
    // Fallback: scan all services (e.g. if UUID casing differs).
    for (final svc in services) {
      for (final c in svc.characteristics) {
        if (_uuidMatch(c.uuid, _kCharUuid)) return c;
      }
    }
    return null;
  }

  static bool _uuidMatch(Guid a, String b) {
    final as = a.toString().toLowerCase();
    final bs = b.toLowerCase();
    return as == bs || as == bs.substring(4, 8);
  }

  // ── raw notification → JSON framing ──────────────────────────────────────

  void _onRawBytes(List<int> bytes) {
    _buf += utf8.decode(bytes, allowMalformed: true);
    if (_buf.length > 10000) {
      debugPrint('BleSessionSync: buffer overflow, clearing');
      _buf = '';
      return;
    }

    while (true) {
      final start = _buf.indexOf('{');
      if (start == -1) { _buf = ''; break; }
      if (start > 0) { _buf = _buf.substring(start); }

      int depth = 0, end = -1;
      bool inStr = false, esc = false;
      for (int i = 0; i < _buf.length; i++) {
        final ch = _buf[i];
        if (esc) { esc = false; continue; }
        if (ch == '\\') { esc = true; continue; }
        if (ch == '"') { inStr = !inStr; continue; }
        if (inStr) continue;
        if (ch == '{') {
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) { end = i; break; }
        }
      }
      if (end == -1) {
        if (_buf.length > 5000) _buf = '';
        break;
      }

      final chunk = _buf.substring(0, end + 1).trim();
      _buf = _buf.substring(end + 1);
      try {
        final parsed = jsonDecode(chunk) as Map<String, dynamic>;
        _dispatch(parsed);
      } catch (_) {}
    }
  }

  void _dispatch(Map<String, dynamic> msg) {
    final completer = _waitCompleter;
    final matcher = _waitMatcher;
    if (completer != null && !completer.isCompleted) {
      if (matcher == null || matcher(msg)) {
        _waitCompleter = null;
        _waitMatcher = null;
        completer.complete(msg);
      }
    }
  }

  // ── waiting helpers ───────────────────────────────────────────────────────

  /// Wait for the next packet that satisfies [matcher], up to [timeout].
  /// Returns null on timeout.
  Future<Map<String, dynamic>?> _waitFor(
    bool Function(Map<String, dynamic>) matcher, {
    required Duration timeout,
  }) async {
    final c = Completer<Map<String, dynamic>>();
    _waitCompleter = c;
    _waitMatcher = matcher;
    try {
      return await c.future.timeout(timeout, onTimeout: () {
        _waitCompleter = null;
        _waitMatcher = null;
        return <String, dynamic>{};
      });
    } catch (_) {
      _waitCompleter = null;
      _waitMatcher = null;
      return null;
    }
  }

  // ── command write ─────────────────────────────────────────────────────────

  Future<bool> _send(Map<String, dynamic> cmd) async {
    final char = _char;
    if (char == null) return false;
    try {
      final payload = utf8.encode(jsonEncode(cmd));
      await char.write(
        payload,
        withoutResponse: char.properties.writeWithoutResponse,
      );
      debugPrint('[SESSION] TX: ${jsonEncode(cmd)}');
      return true;
    } catch (e) {
      debugPrint('[SESSION] TX failed: $e');
      return false;
    }
  }

  // ── main fetch loop ───────────────────────────────────────────────────────

  Future<void> _runFetchLoop() async {
    // Keep fetching until the device says n==0 (drained).
    while (true) {
      if (!_running) return;

      // Send FETCH_SESSIONS, wait up to 5 s for SESS_HDR; retry once.
      Map<String, dynamic>? hdr = await _fetchWithRetry();
      if (hdr == null) {
        debugPrint('[SESSION] No SESS_HDR after retries — giving up');
        return;
      }

      if (hdr['err']?.toString() == 'MTU_TOO_SMALL') {
        debugPrint('[SESSION] SESS_HDR err=MTU_TOO_SMALL — requesting MTU 247');
        if (Platform.isAndroid) {
          try {
            await _device.requestMtu(247, timeout: 3);
          } catch (_) {}
        }
        // Retry once after MTU fix.
        hdr = await _fetchWithRetry();
        if (hdr == null) return;
      }

      final n = (hdr['n'] as num?)?.toInt() ?? 0;
      final xfer = hdr['xfer'];
      debugPrint('[SESSION] SESS_HDR n=$n xfer=$xfer');

      if (n == 0) {
        debugPrint('[SESSION] Device drained — sync complete');
        return;
      }

      // Collect SESS_DATA packets until SESS_END.
      final received = await _collectSession(n, xfer);
      if (received == null) return; // stall/disconnect

      final pk = received.pk;
      final packets = received.packets;
      final missing = <int>[
        for (int i = 0; i < pk; i++)
          if (!packets.containsKey(i)) i,
      ];

      // Retry loop for NACK.
      int nackRounds = 0;
      const maxNackRounds = 5;
      while (missing.isNotEmpty && nackRounds < maxNackRounds) {
        nackRounds++;
        debugPrint('[SESSION] Sending NACK for ${missing.length} packets: $missing');
        final nack = missing.take(16).toList();
        await _send({'cmd': 'ACK_SESSIONS', 'nack': nack, 'xfer': xfer});

        final retx = await _collectSession(n, xfer);
        if (retx == null) return;
        for (final entry in retx.packets.entries) {
          packets[entry.key] = entry.value;
        }
        missing.removeWhere((i) => packets.containsKey(i));
      }

      if (missing.isNotEmpty) {
        debugPrint('[SESSION] Still missing ${missing.length} packets after $nackRounds rounds — skipping');
      }

      // Persist all received sessions.
      for (final rec in packets.values) {
        await _persist(rec);
      }

      // ACK success.
      bool acked = false;
      int ackAttempts = 0;
      while (!acked && ackAttempts < 3) {
        ackAttempts++;
        final sent = await _send({'cmd': 'ACK_SESSIONS', 'ok': true, 'xfer': xfer});
        if (!sent) break;

        // Wait briefly for a possible error response.
        final ackResp = await _waitFor(
          (m) => m['t']?.toString().toUpperCase() == 'ACK' &&
              m['cmd']?.toString().toUpperCase() == 'ACK_SESSIONS',
          timeout: const Duration(seconds: 3),
        );

        if (ackResp == null || ackResp.isEmpty || ackResp['ok'] == true) {
          acked = true;
        } else {
          final err = ackResp['err']?.toString();
          debugPrint('[SESSION] ACK_SESSIONS nack: err=$err');
          if (err == 'BAD_XFER') {
            // Echo the wrong xfer back — firmware will tell us the right one.
            // Just retry with same xfer value; a real implementation would use
            // the corrected xfer from the error response if the firmware provides it.
            continue;
          } else if (err == 'NOT_WAITING') {
            // Device dropped this transfer window. Restart.
            break;
          } else {
            acked = true; // Unknown error; treat as done.
          }
        }
      }

      // Loop: fetch again (device will return n==0 when fully drained).
    }
  }

  Future<Map<String, dynamic>?> _fetchWithRetry() async {
    for (int attempt = 0; attempt < 2; attempt++) {
      final sent = await _send({'cmd': 'FETCH_SESSIONS'});
      if (!sent) return null;

      final hdr = await _waitFor(
        (m) => m['t']?.toString().toUpperCase() == 'SESS_HDR',
        timeout: const Duration(seconds: 5),
      );
      if (hdr != null && hdr.isNotEmpty) return hdr;
      debugPrint('[SESSION] No SESS_HDR (attempt ${attempt + 1})');
    }
    return null;
  }

  // ── session packet collection ─────────────────────────────────────────────

  /// Accumulates SESS_DATA packets until SESS_END.
  /// Returns null if the stream stalls (10 s between packets).
  Future<_CollectedSession?> _collectSession(int n, dynamic xfer) async {
    final packets = <int, _SessionRecord>{};
    int pk = n; // updated when SESS_END arrives

    while (true) {
      final msg = await _waitFor(
        (m) {
          final t = m['t']?.toString().toUpperCase();
          return t == 'SESS_DATA' || t == 'SESS_END';
        },
        timeout: const Duration(seconds: 10),
      );

      if (msg == null || msg.isEmpty) {
        debugPrint('[SESSION] Stream stall — restarting fetch');
        return null;
      }

      final t = msg['t']?.toString().toUpperCase();

      if (t == 'SESS_END') {
        pk = (msg['pk'] as num?)?.toInt() ?? pk;
        debugPrint('[SESSION] SESS_END pk=$pk received=${packets.length}');
        return _CollectedSession(pk: pk, packets: packets);
      }

      // SESS_DATA
      final q = (msg['q'] as num?)?.toInt() ?? -1;
      if (q < 0) continue;

      final tyRaw = msg['ty']?.toString().toLowerCase();
      final type = tyRaw == 'posture' || tyRaw == '1'
          ? 'posture'
          : (tyRaw == 'therapy' || tyRaw == '2' ? 'therapy' : null);
      if (type == null) {
        debugPrint('[SESSION] Unknown ty=$tyRaw in SESS_DATA, skipping');
        continue;
      }

      final ts = (msg['ts'] as num?)?.toInt() ?? 0;
      final d = (msg['d'] as num?)?.toInt() ?? 0;
      final wc = (msg['wc'] as num?)?.toInt() ?? 0;
      final wd = (msg['wd'] as num?)?.toInt() ?? 0;
      final tsSynced = msg['tss'] == true || msg['tss'] == 1;
      final therapyPatt = (msg['tp'] as num?)?.toInt();

      debugPrint(
        '[SESSION] SESS_DATA q=$q ty=$type ts=$ts d=${d}s wc=$wc wd=$wd',
      );

      packets[q] = _SessionRecord(
        q: q,
        type: type,
        startTsEpoch: ts,
        durationSec: d,
        wrongCount: wc,
        wrongDurSec: wd,
        tsSynced: tsSynced,
        therapyPattern: therapyPatt,
      );
    }
  }

  // ── persistence ───────────────────────────────────────────────────────────

  Future<void> _persist(_SessionRecord rec) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('BleSessionSync: no authenticated user, skipping persist');
      return;
    }

    final effectiveTs =
        rec.startTsIso ?? DateTime.now().toUtc().toIso8601String();

    try {
      final db = SessionDatabase.instance;
      final existingId = await db.findExistingByFields(
        userId: user.id,
        type: rec.type,
        startTsEpoch: rec.startTsEpoch,
        durationSec: rec.durationSec,
        wrongCount: rec.wrongCount,
        wrongDurSec: rec.wrongDurSec,
      );

      if (existingId != null) {
        debugPrint(
          '[SESSION] Dedup: row exists id=$existingId ty=${rec.type} ts=${rec.startTsEpoch}',
        );
      } else {
        final id = await db.insertSession({
          'user_id': user.id,
          'type': rec.type,
          'start_ts': effectiveTs,
          'duration_sec': rec.durationSec,
          'wrong_count': rec.type == 'posture' ? rec.wrongCount : null,
          'wrong_dur_sec': rec.type == 'posture' ? rec.wrongDurSec : null,
          'therapy_pattern': rec.type == 'therapy' ? rec.therapyPattern : null,
          'ts_synced': rec.tsSynced,
          'sync_status': 0,
        });
        debugPrint('[SESSION] Inserted id=$id ty=${rec.type} ts=${rec.startTsEpoch}');
        _sentCount++;
        _emitProgress(_sentCount);
        SessionSyncService.instance.triggerSync();
      }
    } catch (e) {
      debugPrint('[SESSION] Persist failed: $e');
      _emitError(e);
    }
  }

  // ── progress / error ──────────────────────────────────────────────────────

  void _emitProgress(int sent) {
    if (_progressController.isClosed) return;
    _progressController.add(
      SyncProgress(sent: sent, total: sent, complete: false),
    );
  }

  void _emitComplete() {
    if (_complete) return;
    _complete = true;
    _running = false;
    debugPrint('[SESSION] ── Sync complete ── total_saved=$_sentCount');
    if (_progressController.isClosed) return;
    _progressController.add(
      SyncProgress(sent: _sentCount, total: _sentCount, complete: true),
    );
  }

  void _emitError(Object error) {
    if (_progressController.isClosed) return;
    _progressController.add(
      SyncProgress(sent: _sentCount, total: _sentCount, complete: false, error: error),
    );
  }
}

class _CollectedSession {
  _CollectedSession({required this.pk, required this.packets});
  final int pk;
  final Map<int, _SessionRecord> packets;
}

/// Derive the "good posture" % shown in Analytics from the raw BLE fields.
int goodPostureScore({required int durationSec, required int wrongDurSec}) {
  if (durationSec <= 0) return 100;
  return (100 - (wrongDurSec / durationSec * 100)).round().clamp(0, 100);
}