import 'dart:convert';

enum OperationKind { ulang, plant, mortality, task }

/// An in-memory submission; it is never persisted or queued on the device.
class RecordSubmission {
  const RecordSubmission({
    required this.id,
    required this.uid,
    required this.kind,
    required this.payload,
    required this.observedAt,
  });
  final String id;
  final String uid;
  final OperationKind kind;
  final Map<String, dynamic> payload;
  final DateTime observedAt;
}

class OfflineApproval {
  const OfflineApproval({
    required this.uid,
    required this.checkedAt,
    required this.profile,
  });
  static const lifetime = Duration(days: 7);
  final String uid;
  final DateTime checkedAt;
  final Map<String, dynamic> profile;
  bool permits(String? currentUid, DateTime now) =>
      uid == currentUid &&
      profile['role'] == 'user' &&
      profile['status'] == 'active' &&
      !now.isBefore(checkedAt) &&
      now.difference(checkedAt) < lifetime;
  Map<String, Object?> toRow() => {
    'uid': uid,
    'checkedAt': checkedAt.millisecondsSinceEpoch,
    'profile': jsonEncode(profile),
  };
  factory OfflineApproval.fromRow(Map<String, Object?> row) => OfflineApproval(
    uid: row['uid'] as String,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(
      row['checkedAt'] as int,
      isUtc: true,
    ),
    profile: jsonDecode(row['profile'] as String) as Map<String, dynamic>,
  );
}

class SyncConflict implements Exception {
  const SyncConflict(this.message);
  final String message;
  @override
  String toString() => message;
}
