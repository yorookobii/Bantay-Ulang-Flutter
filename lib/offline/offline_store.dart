import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'offline_models.dart';

/// Stores approval metadata and timestamps for offline viewing only.
class OfflineStore {
  OfflineStore(this.db);
  final Database db;

  static Future<OfflineStore> open({
    String? databasePath,
    DatabaseFactory? factory,
  }) async {
    final backend = factory ?? databaseFactory;
    final location =
        databasePath ??
        path.join(await backend.getDatabasesPath(), 'bantay_offline.db');
    final db = await backend.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE approvals (uid TEXT PRIMARY KEY, checkedAt INTEGER NOT NULL, profile TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE cache_stamps (uid TEXT NOT NULL, source TEXT NOT NULL, confirmedAt INTEGER NOT NULL, PRIMARY KEY(uid,source))',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Explicitly discard all old local records, across every account.
            // The database upgrade is atomic and never touches Firestore.
            await db.execute('DROP TABLE IF EXISTS operations');
            await db.execute('DROP TABLE IF EXISTS recalculations');
          }
        },
        onOpen: (db) async {
          // Also clean up leftover tables on already-upgraded installations.
          // Retain approval/viewing metadata; never delete server records.
          await db.transaction((tx) async {
            await tx.execute('DROP TABLE IF EXISTS operations');
            await tx.execute('DROP TABLE IF EXISTS recalculations');
          });
        },
      ),
    );
    return OfflineStore(db);
  }

  Future<OfflineApproval?> approval(String uid) async {
    final rows = await db.query(
      'approvals',
      where: 'uid = ?',
      whereArgs: [uid],
    );
    return rows.isEmpty ? null : OfflineApproval.fromRow(rows.single);
  }

  Future<void> saveApproval(OfflineApproval approval) => db
      .insert(
        'approvals',
        approval.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      )
      .then((_) {});
  Future<void> clearApproval(String uid) =>
      db.delete('approvals', where: 'uid = ?', whereArgs: [uid]).then((_) {});
  Future<void> clearCacheStamps() => db.delete('cache_stamps').then((_) {});
  Future<DateTime?> lastConfirmed(String uid, String source) async {
    final rows = await db.query(
      'cache_stamps',
      where: 'uid = ? AND source = ?',
      whereArgs: [uid, source],
    );
    return rows.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            rows.single['confirmedAt'] as int,
          );
  }

  Future<void> confirmCache(String uid, String source, DateTime at) => db
      .insert('cache_stamps', {
        'uid': uid,
        'source': source,
        'confirmedAt': at.millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace)
      .then((_) {});
  Future<void> close() async {
    await db.close();
  }
}
