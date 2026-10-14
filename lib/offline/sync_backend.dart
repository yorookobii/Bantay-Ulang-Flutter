import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'offline_models.dart';

abstract interface class SyncBackend {
  Future<void> upload(RecordSubmission operation, {bool Function()? canSubmit});
  Future<void> recalculate(
    String cycleId,
    int cycleStart, {
    bool Function()? canSubmit,
  });
  Future<void> recalculateLatest({bool Function()? canSubmit});
}

class FirestoreSyncBackend implements SyncBackend {
  FirestoreSyncBackend(this.firestore, this.currentUid);
  final FirebaseFirestore firestore;
  final String? Function() currentUid;
  static const server = GetOptions(source: Source.server);
  static String mortalityId(String cycleId, int cycleStart, int week) =>
      'offline_${base64Url.encode(utf8.encode(cycleId)).replaceAll('=', '')}_${cycleStart}_$week';

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _ownedLog(
    RecordSubmission op,
  ) async {
    // A document-ID filter can make rules inspect the actual missing document
    // even with an owner filter. Query owned logs, then match the ID locally.
    final records = await firestore
        .collection('logs')
        .where('createdBy', isEqualTo: op.uid)
        .get(server);
    for (final record in records.docs) {
      if (record.id == op.id) return record;
    }
    return null;
  }

  @override
  Future<void> upload(RecordSubmission op, {bool Function()? canSubmit}) async {
    void check() {
      if (currentUid() != op.uid || canSubmit?.call() == false) {
        throw const SyncConflict(
          'The submission session changed. Please try again.',
        );
      }
    }

    check();
    if (currentUid() != op.uid) {
      throw const SyncConflict(
        'Log in with the account that recorded this entry.',
      );
    }
    final p = op.payload;
    final log = firestore.collection('logs').doc(op.id);
    final growth = firestore.collection('ulang_growth_records').doc(op.id);
    final death = op.kind == OperationKind.mortality
        ? firestore
              .collection('mortality_records')
              .doc(
                mortalityId(
                  p['cycleId'] as String,
                  p['cycleStart'] as int,
                  p['weekNumber'] as int,
                ),
              )
        : null;
    // Also recognize records created by earlier app/web versions with random IDs.
    var legacyDuplicate = false;
    if (death != null) {
      final latest = await firestore
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get(server);
      if (latest.docs.isEmpty ||
          latest.docs.first.id != p['cycleId'] ||
          (latest.docs.first.data()['cycleStart'] as Timestamp?)
                  ?.millisecondsSinceEpoch !=
              p['cycleStart']) {
        // First reconcile a previously committed operation even if the cycle changed.
        final existing = await _ownedLog(op);
        final recorded = await death.get(server);
        if (existing != null &&
            recorded.exists &&
            existing.data()['createdBy'] == op.uid) {
          return;
        }
        throw const SyncConflict(
          'The farming cycle changed. Please review your entry before submitting again.',
        );
      }
      final records = await firestore
          .collection('mortality_records')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(
              p['cycleStart'] as int,
            ),
          )
          .get(server);
      legacyDuplicate = records.docs.any(
        (d) => d.id != death.id && d.data()['weekNumber'] == p['weekNumber'],
      );
    }
    await firestore.runTransaction((tx) async {
      check();
      if (currentUid() != op.uid) {
        throw const SyncConflict(
          'The active account changed. Please sign in again.',
        );
      }
      // Recheck approval against the server inside the transaction.
      final account = await tx.get(firestore.collection('users').doc(op.uid));
      if (account.data()?['status'] != 'active' ||
          account.data()?['role'] != 'user') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Account approval changed.',
        );
      }
      if (op.kind == OperationKind.task) {
        final ref = firestore.collection('tasks').doc(p['taskId'] as String);
        final task = await tx.get(ref);
        if (!task.exists || task.data()?['assignedTo'] != op.uid) {
          throw const SyncConflict(
            'This task was deleted or reassigned. No server data was changed.',
          );
        }
        if (task.data()?['status'] == 'done') return;
        if (task.data()?['status'] != 'pending') {
          throw const SyncConflict(
            'The task status changed. Please review it before completing it.',
          );
        }
        check();
        tx.update(ref, {'status': 'done'});
        return;
      }
      // An owner-only rule cannot authorize get() on a nonexistent log:
      // there is no resource.data.createdBy yet. Query with the ownership
      // constraint first; only transaction-read an existing owned document.
      final ownedLog = await _ownedLog(op);
      final savedLog = ownedLog == null ? null : await tx.get(log);
      DocumentSnapshot<Map<String, dynamic>>? savedPair;
      if (op.kind == OperationKind.ulang) savedPair = await tx.get(growth);
      if (death != null) savedPair = await tx.get(death);
      if (savedLog?.exists == true) {
        if (savedLog!.data()?['createdBy'] != op.uid ||
            savedLog.data()?['type'] != op.kind.name ||
            (savedPair != null && !savedPair.exists)) {
          throw const SyncConflict(
            'An existing record does not match this entry. Please contact an admin.',
          );
        }
        return; // Server committed before the phone could record its acknowledgment.
      }
      if (savedPair?.exists == true) {
        throw const SyncConflict(
          'A record already exists for this entry or week. Please review the records.',
        );
      }
      if (death != null) {
        final cycle = await tx.get(
          firestore.collection('growth_indicators').doc(p['cycleId'] as String),
        );
        if ((cycle.data()?['cycleStart'] as Timestamp?)
                ?.millisecondsSinceEpoch !=
            p['cycleStart']) {
          throw const SyncConflict(
            'The farming cycle changed. Please review this entry.',
          );
        }
        if (legacyDuplicate) {
          throw const SyncConflict(
            'Mortality is already recorded for this week.',
          );
        }
      }
      check();
      final at = Timestamp.fromDate(op.observedAt);
      final common = <String, dynamic>{
        'createdBy': op.uid,
        'createdByName':
            account.data()?['fullName'] ?? p['createdByName'] ?? '',
        'createdByEmail': account.data()?['email'] ?? p['createdByEmail'] ?? '',
        'type': op.kind.name,
        'createdAt': FieldValue.serverTimestamp(),
        'observedAt': at,
      };
      switch (op.kind) {
        case OperationKind.ulang:
          tx.set(log, {
            ...common,
            'title': 'Ulang Log',
            'description': 'Laki: ${p['size']}cm • Timbang: ${p['weight']}g',
            'size': p['size'],
            'weight': p['weight'],
          });
          tx.set(growth, {
            'size': double.parse(p['size'] as String),
            'weight': double.parse(p['weight'] as String),
            'recordedBy': op.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'observedAt': at,
          });
        case OperationKind.plant:
          tx.set(log, {
            ...common,
            'title': p['plantName'],
            'plantName': p['plantName'],
            'description':
                'Taas: ${p['height']}cm • Yugto: ${p['stage']} • Kondisyon: ${p['condition']}',
            'height': p['height'],
            'stage': p['stage'],
            'condition': p['condition'],
          });
        case OperationKind.mortality:
          tx.set(death!, {
            'deathCount': p['deathCount'],
            'weekNumber': p['weekNumber'],
            'recordedBy': op.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'observedAt': at,
          });
          tx.set(log, {
            ...common,
            'title': 'Mortality Log',
            'description':
                'Namatay: ${p['deathCount']} ulang • Linggo: ${p['weekNumber']}',
            'deathCount': p['deathCount'],
            'weekNumber': p['weekNumber'],
          });
        case OperationKind.task:
          break;
      }
    });
  }

  @override
  Future<void> recalculateLatest({bool Function()? canSubmit}) async {
    if (canSubmit?.call() == false) {
      throw const SyncConflict('The session changed.');
    }
    final latest = await firestore
        .collection('growth_indicators')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get(server);
    if (latest.docs.isEmpty) return;
    final cycle = latest.docs.first;
    final start = cycle.data()['cycleStart'] as Timestamp?;
    if (start != null) {
      await recalculate(
        cycle.id,
        start.millisecondsSinceEpoch,
        canSubmit: canSubmit,
      );
    }
  }

  @override
  Future<void> recalculate(
    String cycleId,
    int cycleStart, {
    bool Function()? canSubmit,
  }) async {
    final owner = currentUid();
    if (owner == null) throw const SyncConflict('Please log in again.');
    await firestore.runTransaction((tx) async {
      if (currentUid() != owner || canSubmit?.call() == false) {
        throw const SyncConflict('The active account changed.');
      }
      final account = await tx.get(firestore.collection('users').doc(owner));
      if (account.data()?['status'] != 'active' ||
          account.data()?['role'] != 'user') {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      }
      final ref = firestore.collection('growth_indicators').doc(cycleId);
      final cycle = await tx.get(ref);
      final data = cycle.data();
      if ((data?['cycleStart'] as Timestamp?)?.millisecondsSinceEpoch !=
          cycleStart) {
        return;
      }
      // Read the summary version before querying confirmed deaths. If another
      // recalculation commits first, retry this entire query with fresh totals.
      final latest = await firestore
          .collection('growth_indicators')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get(server);
      if (latest.docs.isEmpty || latest.docs.first.id != cycleId) return;
      final records = await firestore
          .collection('mortality_records')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromMillisecondsSinceEpoch(
              cycleStart,
            ),
          )
          .get(server);
      final total = records.docs
          .where((d) {
            final observed = d.data()['observedAt'] as Timestamp?;
            return observed == null ||
                observed.millisecondsSinceEpoch >= cycleStart;
          })
          .fold<int>(
            0,
            (deaths, d) =>
                deaths + ((d.data()['deathCount'] as num?)?.toInt() ?? 0),
          );
      final stock = (data?['initialStock'] as num?)?.toDouble() ?? 0;
      if (currentUid() != owner || canSubmit?.call() == false) {
        throw const SyncConflict('The session changed.');
      }
      if (stock > 0) {
        tx.update(ref, {
          'survivalRate': ((stock - total) / stock * 100).clamp(0, 100),
        });
      }
    });
  }
}
