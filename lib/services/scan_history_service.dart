import 'dart:convert';
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

class ScanHistoryService {
  static Future<Database>? _database;
  static Future<Database> get database => _database ??= openDatabase(
    'scan_history.db',
    version: 2,
    onCreate: (db, version) async {
      await db.execute(
        'CREATE TABLE scans (entry_id TEXT PRIMARY KEY, payload TEXT NOT NULL, confirmed INTEGER NOT NULL DEFAULT 0, error TEXT, scan_key TEXT NOT NULL)',
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
    },
  );
  static Future<void> close() async {
    final pending = _database;
    if (pending != null) await (await pending).close();
    _database = null;
  }

  static bool syncing = false;

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

  static Future<void> _status(String id, bool confirmed, String? error) async {
    await (await database).update(
      'scans',
      {'confirmed': confirmed ? 1 : 0, 'error': error},
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
          },
        )
        .toList();
  }

  // Reconcile every local entry, including previously acknowledged uploads.
  static Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    try {
      final all = await entries();
      var rejected = 0;
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
          await _status(
            id,
            ok,
            ok ? null : errors[id]?.toString() ?? 'Not confirmed by server',
          );
          if (!ok) rejected++;
        }
      }
      if (rejected > 0) {
        throw ApiException(
          '$rejected entries need attention. See the messages below.',
        );
      }
    } finally {
      syncing = false;
    }
  }
}
