import 'package:shared_preferences/shared_preferences.dart';
import 'offline_store.dart';

class LocalRecordCleanupFailure implements Exception {
  const LocalRecordCleanupFailure();

  @override
  String toString() =>
      'Old local records could not be cleared. Close the app completely and reopen it.';
}

/// One-time reset requested for records left by the old offline save flow.
/// Call before any Firestore reads, listeners or writes are started.
Future<void> clearLegacyFirestoreRecords({
  required OfflineStore store,
  required Future<void> Function() clearPersistence,
  SharedPreferences? preferences,
}) async {
  const completedKey = 'legacy_firestore_records_cleared_v1';
  try {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    if (prefs.getBool(completedKey) == true) return;
    // Firestore keeps its own queued writes, separate from our SQLite queue.
    // Clearing persistence discards those writes and all cached documents.
    await clearPersistence();
    await store.clearCacheStamps();
    if (!await prefs.setBool(completedKey, true)) {
      throw const LocalRecordCleanupFailure();
    }
  } catch (_) {
    // Do not start Firestore and replay old writes if cleanup failed.
    throw const LocalRecordCleanupFailure();
  }
}
