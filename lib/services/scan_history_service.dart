import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'api_service.dart';

class LocalDuplicateScanException implements Exception {
  final bool confirmed;
  const LocalDuplicateScanException(this.confirmed);
  @override
  String toString() => confirmed
      ? 'This rider is already checked in at this checkpoint on this device.'
      : 'This rider is already saved on this device. Use Settings → Scan history & sync to upload the existing entry.';
}

class ScanQueueStatus {
  final int pending;
  final int rejected;
  final bool uploading;
  final String? error;
  const ScanQueueStatus({
    this.pending = 0,
    this.rejected = 0,
    this.uploading = false,
    this.error,
  });
}

class ScanHistoryService {
  static Future<Database>? _database;
  static Future<Database> get database => _database ??= openDatabase(
    'scan_history.db',
    version: 3,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE scans (entry_id TEXT PRIMARY KEY, payload TEXT NOT NULL, confirmed INTEGER NOT NULL DEFAULT 0, error TEXT, scan_key TEXT NOT NULL, rejected INTEGER NOT NULL DEFAULT 0)',
      );
      await db.execute('CREATE INDEX scans_key ON scans(scan_key)');
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute('ALTER TABLE scans ADD COLUMN scan_key TEXT');
        for (final row in await db.query('scans')) {
          final entry =
              jsonDecode(row['payload'] as String) as Map<String, dynamic>;
          await db.update(
            'scans',
            {
              'scan_key': _key(
                entry['rider_id'] as String,
                entry['category'] as String,
                entry['checkpoint'] as String,
              ),
            },
            where: 'entry_id = ?',
            whereArgs: [row['entry_id']],
          );
        }
        // Keep all historical rows, including any pre-upgrade duplicates.
        await db.execute('CREATE INDEX scans_key ON scans(scan_key)');
      }
      if (oldVersion < 3) {
        await db.execute(
          'ALTER TABLE scans ADD COLUMN rejected INTEGER NOT NULL DEFAULT 0',
        );
      }
    },
  );
  static Future<void> close() async {
    stopAutomaticSync();
    try {
      await _activeSync;
    } catch (_) {
      /* Entries remain durable. */
    }
    final pending = _database;
    if (pending != null) await (await pending).close();
    _database = null;
  }

  static Future<void>? _activeSync;
  static bool get syncing => _activeSync != null;
  static final queueStatus = ValueNotifier(const ScanQueueStatus());
  static Timer? _retryTimer;
  static bool _automatic = false;
  static int _failures = 0;
  static int _workerGeneration = 0;

  static void startAutomaticSync() {
    if (_automatic) return;
    _automatic = true;
    _schedule(Duration.zero);
  }

  static void stopAutomaticSync() {
    _automatic = false;
    _workerGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  static void _schedule(Duration delay) {
    if (!_automatic) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_uploadPending());
    });
  }

  static Future<void> _uploadPending() async {
    final generation = _workerGeneration;
    try {
      await syncPending();
      _failures = 0;
    } catch (_) {
      _failures = min(_failures + 1, 5);
    } finally {
      // Poll while foregrounded; a newly saved scan can wake an idle worker.
      if (generation == _workerGeneration) {
        _schedule(
          Duration(
            seconds: _failures == 0 ? 30 : min(5 * (1 << (_failures - 1)), 60),
          ),
        );
      }
    }
  }

  static Future<void> refreshQueueStatus({
    String? error,
    bool? uploading,
  }) async {
    try {
      final rows = await (await database).rawQuery(
        'SELECT rejected, COUNT(*) AS total FROM scans WHERE confirmed = 0 GROUP BY rejected',
      );
      int pending = 0;
      int rejected = 0;
      for (final row in rows) {
        if (row['rejected'] == 1) {
          rejected = row['total'] as int;
        } else {
          pending = row['total'] as int;
        }
      }
      queueStatus.value = ScanQueueStatus(
        pending: pending,
        rejected: rejected,
        uploading: uploading ?? syncing,
        error: error,
      );
    } catch (_) {
      queueStatus.value = ScanQueueStatus(
        pending: queueStatus.value.pending,
        rejected: queueStatus.value.rejected,
        uploading: uploading ?? syncing,
        error: 'Could not read saved scan status. Open scan history to retry.',
      );
    }
  }

  static String _key(String rider, String category, String checkpoint) =>
      jsonEncode([rider.trim(), category.trim(), checkpoint.trim()]);

  static Future<Map<String, dynamic>> record({
    required String riderId,
    required String riderName,
    required String category,
    required String checkpoint,
    required String scannedBy,
  }) async {
    final random = Random.secure();
    final entry = <String, dynamic>{
      'entry_id': List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'rider_id': riderId,
      'rider_name': riderName,
      'category': category,
      'checkpoint': checkpoint,
      'scanned_by': scannedBy,
      'scanned_at': DateTime.now().toUtc().toIso8601String(),
    };
    final key = _key(riderId, category, checkpoint);
    // Check and insert in one transaction, including concurrent button actions.
    await (await database).transaction((txn) async {
      final existing = await txn.query(
        'scans',
        columns: ['confirmed'],
        where: 'scan_key = ?',
        whereArgs: [key],
        orderBy: 'confirmed DESC',
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw LocalDuplicateScanException(existing.first['confirmed'] == 1);
      }
      await txn.insert('scans', {
        'entry_id': entry['entry_id'],
        'payload': jsonEncode(entry),
        'scan_key': key,
      });
    });
    await refreshQueueStatus();
    if (_automatic && !syncing && _failures == 0) _schedule(Duration.zero);
    return entry;
  }

  static Future<void> submit(Map<String, dynamic> entry) async {
    try {
      await ApiService.uploadScanEntry(entry);
      await _status(entry['entry_id'] as String, true, null);
    } catch (e) {
      await _status(entry['entry_id'] as String, false, e.toString());
      rethrow;
    }
  }

  static Future<void> _status(
    String id,
    bool confirmed,
    String? error, {
    bool rejected = false,
  }) async {
    await (await database).update(
      'scans',
      {
        'confirmed': confirmed ? 1 : 0,
        'error': error,
        'rejected': rejected ? 1 : 0,
      },
      where: 'entry_id = ?',
      whereArgs: [id],
    );
  }

  static Future<List<Map<String, dynamic>>> entries() async {
    final rows = await (await database).query('scans', orderBy: 'rowid DESC');
    return rows
        .map(
          (r) => <String, dynamic>{
            ...jsonDecode(r['payload'] as String) as Map<String, dynamic>,
            'confirmed': r['confirmed'] == 1,
            'error': r['error'],
            'rejected': r['rejected'] == 1,
          },
        )
        .toList();
  }

  // Automatic uploads only send pending entries. Manual sync also reconciles
  // confirmed entries and retries entries previously rejected by the server.
  static Future<void> syncPending() => _activeSync ?? _startSync(false);

  static Future<void> sync() async {
    // Do not report manual success just because an automatic upload is running.
    while (_activeSync != null) {
      try {
        await _activeSync;
      } catch (_) {
        /* Retry via full reconciliation. */
      }
    }
    await _startSync(true);
  }

  static Future<void> _startSync(bool reconcileAll) {
    final completer = Completer<void>();
    _activeSync = completer.future;
    unawaited(() async {
      Object? failure;
      StackTrace? failureStack;
      try {
        await refreshQueueStatus();
        await _syncEntries(reconcileAll);
      } catch (e, stack) {
        failure = e;
        failureStack = stack;
      }
      await refreshQueueStatus(error: failure?.toString(), uploading: false);
      _activeSync = null;
      if (failure != null) {
        completer.completeError(failure, failureStack);
      } else {
        completer.complete();
      }
    }());
    return completer.future;
  }

  static Future<void> _syncEntries(bool reconcileAll) async {
    final rows = await (await database).query(
      'scans',
      where: reconcileAll ? null : 'confirmed = 0 AND rejected = 0',
      orderBy: 'rowid ASC',
    );
    final all = rows
        .map((r) => jsonDecode(r['payload'] as String) as Map<String, dynamic>)
        .toList();
    var rejected = 0;
    var unconfirmed = 0;
    for (var offset = 0; offset < all.length; offset += 50) {
      final batch = all.sublist(offset, min(offset + 50, all.length));
      final result = await ApiService.syncScanEntries(batch);
      final confirmed = (result['confirmed_ids'] as List)
          .cast<String>()
          .toSet();
      final errors = result['errors'] as Map<String, dynamic>;
      for (final entry in batch) {
        final id = entry['entry_id'] as String;
        final ok = confirmed.contains(id);
        final denied = !ok && errors.containsKey(id);
        await _status(
          id,
          ok,
          ok ? null : errors[id]?.toString() ?? 'Not confirmed by server',
          rejected: denied,
        );
        if (denied) rejected++;
        if (!ok && !denied) unconfirmed++;
      }
      await refreshQueueStatus();
    }
    if (unconfirmed > 0) {
      throw ApiException('$unconfirmed uploads not confirmed. Will retry.');
    }
    if (reconcileAll && rejected > 0) {
      throw ApiException(
        '$rejected entries need attention. See the messages below.',
      );
    }
  }
}
