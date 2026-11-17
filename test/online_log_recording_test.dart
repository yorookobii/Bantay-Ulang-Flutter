import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/logs.dart';
import 'package:demo_1_langto/offline/offline_models.dart';
import 'package:demo_1_langto/offline/offline_services.dart';
import 'package:demo_1_langto/offline/offline_store.dart';
import 'package:demo_1_langto/offline/session_controller.dart';
import 'package:demo_1_langto/offline/sync_backend.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'support/offline_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  late TestSessionBackend auth;
  late SessionController session;
  late OfflineServices services;
  late _TransactionFirestore firestore;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = await OfflineStore.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    auth = TestSessionBackend();
    session = SessionController(store, auth);
    firestore = _TransactionFirestore();
    services = OfflineServices(
      store,
      session,
      FirestoreSyncBackend(firestore, () => session.uid),
    );
    OfflineServices.current = services;
    await session.acceptLogin('farmer-a', {
      'role': 'user',
      'status': 'active',
    }, emailVerified: true);
    await firestore.doc('users/farmer-a').set({
      'role': 'user',
      'status': 'active',
      'fullName': 'Test Farmer',
      'email': 'test@example.com',
    });
    final start = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await firestore.doc('growth_indicators/cycle').set({
      'timestamp': start,
      'cycleStart': start,
      'initialStock': 100,
    });
  });
  tearDown(() async {
    await services.dispose();
    await auth.events.close();
  });
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => session.logout());
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester, OperationKind kind) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: LogsPage(firestore: firestore)));
    await settle(tester);
    if (kind == OperationKind.plant) {
      await tester.tap(find.text('Tala ng Tanim'));
      await tester.pumpAndSettle();
      for (final choice in ['Mint', 'Malusog (Healthy)', 'Seedling (Punla)']) {
        final index = choice == 'Mint'
            ? 0
            : choice == 'Malusog (Healthy)'
            ? 1
            : 2;
        final dropdown = find.byType(DropdownButtonFormField<String>).at(index);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice).last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).first, '15');
    } else if (kind == OperationKind.mortality) {
      await tester.enterText(find.byType(TextField).at(2), '3');
    } else {
      await tester.enterText(find.byType(TextField).at(0), '5');
      await tester.enterText(find.byType(TextField).at(1), '12');
    }
  }

  String saveLabel(OperationKind kind) => switch (kind) {
    OperationKind.ulang => 'I-save ang Ulang Log',
    OperationKind.plant => 'I-save ang Plant Log',
    _ => 'I-save ang Mortality Log',
  };

  Future<void> submit(WidgetTester tester, OperationKind kind) async {
    final save = find.text(saveLabel(kind));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
  }

  void expectValues(WidgetTester tester, OperationKind kind) {
    final index = kind == OperationKind.mortality ? 2 : 0;
    expect(
      tester
          .widget<TextField>(find.byType(TextField).at(index))
          .controller!
          .text,
      kind == OperationKind.ulang
          ? '5'
          : kind == OperationKind.plant
          ? '15'
          : '3',
    );
  }

  Future<void> expectNothingRecorded(WidgetTester tester) async {
    expect(firestore.transactionCalls, 0);
    await tester.runAsync(() async {
      expect((await firestore.collection('logs').get()).docs, isEmpty);
      expect(
        (await firestore.collection('ulang_growth_records').get()).docs,
        isEmpty,
      );
      expect(
        (await firestore.collection('mortality_records').get()).docs,
        isEmpty,
      );
    });
  }

  for (final kind in [
    OperationKind.ulang,
    OperationKind.plant,
    OperationKind.mortality,
  ]) {
    testWidgets(
      '${kind.name}: offline save retains form values and viewing access',
      (tester) async {
        session.networkLost();
        await openForm(tester, kind);
        await submit(tester, kind);
        expect(find.text('Internet connection is required.'), findsOneWidget);
        expectValues(tester, kind);
        expect(session.canAccess, isTrue);
        expect(find.textContaining('Saved on this device'), findsNothing);
        await expectNothingRecorded(tester);
        await close(tester);
      },
    );
    testWidgets(
      '${kind.name}: stale online state never writes and can recover',
      (tester) async {
        auth.connected = false;
        await openForm(tester, kind);
        await submit(tester, kind);
        expect(find.text('Internet connection is required.'), findsOneWidget);
        expectValues(tester, kind);
        await expectNothingRecorded(tester);
        auth.connected = true;
        await tester.runAsync(() => session.refresh());
        await submit(tester, kind);
        expect(find.textContaining('Matagumpay na na-save'), findsOneWidget);
        await tester.runAsync(() async {
          expect((await firestore.collection('logs').get()).docs, hasLength(1));
        });
        await close(tester);
      },
    );
    testWidgets(
      '${kind.name}: transaction rejection retains values and resets button',
      (tester) async {
        firestore.transactionError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
        await openForm(tester, kind);
        await submit(tester, kind);
        expect(
          find.textContaining('Firebase denied permission'),
          findsOneWidget,
        );
        expectValues(tester, kind);
        expect(find.text(saveLabel(kind)), findsOneWidget);
        await tester.runAsync(() async {
          expect((await firestore.collection('logs').get()).docs, isEmpty);
          expect(
            (await firestore.collection('ulang_growth_records').get()).docs,
            isEmpty,
          );
        });
        await close(tester);
      },
    );
    testWidgets('${kind.name}: repeated taps during server check save once', (
      tester,
    ) async {
      auth.gate = Completer<void>();
      await openForm(tester, kind);
      await submit(tester, kind);
      expect(auth.checks, 1);
      final saving = find.text('Sine-save...');
      await tester.tap(saving);
      await tester.pump();
      auth.gate!.complete();
      await settle(tester);
      expect(auth.checks, 1);
      await tester.runAsync(() async {
        expect((await firestore.collection('logs').get()).docs, hasLength(1));
      });
      await close(tester);
    });
    for (final transition in [
      'logout',
      'account change',
      'access loss',
      'dispose',
      'disconnect',
    ]) {
      testWidgets('${kind.name}: $transition during server check cannot save', (
        tester,
      ) async {
        auth.gate = Completer<void>();
        await openForm(tester, kind);
        await submit(tester, kind);
        if (transition == 'logout' || transition == 'account change') {
          await tester.runAsync(() async {
            await session.logout();
            if (transition == 'account change') {
              auth.uid = 'farmer-b';
              await session.acceptLogin('farmer-b', {
                'role': 'user',
                'status': 'active',
              }, emailVerified: true);
            }
          });
        } else if (transition == 'access loss') {
          await tester.runAsync(() => session.block('Access revoked.'));
        } else if (transition == 'disconnect') {
          auth.connected = false;
          session.networkLost();
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        auth.gate!.complete();
        await settle(tester);
        await expectNothingRecorded(tester);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }
  }
  for (final kind in [
    OperationKind.ulang,
    OperationKind.plant,
    OperationKind.mortality,
  ]) {
    testWidgets(
      '${kind.name}: logout after commit ignores its delayed acknowledgment',
      (tester) async {
        firestore.acknowledgmentGate = Completer<void>();
        await openForm(tester, kind);
        await submit(tester, kind);
        await tester.runAsync(() async {
          expect((await firestore.collection('logs').get()).docs, hasLength(1));
          await session.logout();
        });
        firestore.acknowledgmentGate!.complete();
        await settle(tester);
        expectValues(tester, kind);
        expect(find.textContaining('Matagumpay na na-save'), findsNothing);
        await tester.runAsync(() async {
          final log = (await firestore.collection('logs').get()).docs.single
              .data();
          expect(log['createdBy'], 'farmer-a');
        });
        await close(tester);
      },
    );
  }

  testWidgets('Ulang transaction preserves paired values and updates summary', (
    tester,
  ) async {
    await firestore.doc('mortality_records/deaths').set({
      'createdAt': Timestamp.now(),
      'deathCount': 10,
    });
    await openForm(tester, OperationKind.ulang);
    await submit(tester, OperationKind.ulang);
    await tester.runAsync(() async {
      final log = (await firestore.collection('logs').get()).docs.single;
      final growth = (await firestore.collection('ulang_growth_records').get())
          .docs
          .single;
      expect(growth.id, log.id);
      expect(log.data()['createdBy'], 'farmer-a');
      expect(log.data()['createdByName'], 'Test Farmer');
      expect(log.data()['size'], '5');
      expect(growth.data()['weight'], 12.0);
      expect(growth.data()['observedAt'], log.data()['observedAt']);
      expect(
        (await firestore.doc('growth_indicators/cycle').get())
            .data()!['survivalRate'],
        90,
      );
    });
    await close(tester);
  });
  testWidgets(
    'growth graph includes only records created in the current admin cycle, as weekly medians',
    (tester) async {
      final start = DateTime(2026, 10, 1, 12, 30);
      final nextWeek = start.add(const Duration(days: 7));
      final records = {
        'previous-cycle': {
          'createdAt': Timestamp.fromDate(start),
          'observedAt': Timestamp.fromDate(
            start.subtract(const Duration(microseconds: 1)),
          ),
          'weight': 900.0,
        },
        'delayed-old-upload': {
          'createdAt': Timestamp.fromDate(start.add(const Duration(days: 3))),
          'observedAt': Timestamp.fromDate(
            start.subtract(const Duration(days: 3)),
          ),
          'weight': 900.0,
        },
        'legacy-old': {
          'createdAt': Timestamp.fromDate(
            start.subtract(const Duration(days: 1)),
          ),
          'weight': 900.0,
        },
        'exact-start': {
          'createdAt': Timestamp.fromDate(start),
          'observedAt': Timestamp.fromDate(start),
          'weight': 10.0,
        },
        'current': {
          'createdAt': Timestamp.fromDate(start.add(const Duration(days: 3))),
          'observedAt': Timestamp.fromDate(start.add(const Duration(days: 3))),
          'weight': 20.0,
        },
        'legacy-current': {
          'createdAt': Timestamp.fromDate(start.add(const Duration(days: 5))),
          'weight': 30.0,
        },
        'exact-next-week': {
          'createdAt': Timestamp.fromDate(nextWeek),
          'observedAt': Timestamp.fromDate(nextWeek),
          'weight': 40.0,
        },
      };
      await firestore.doc('growth_indicators/cycle').update({
        'cycleStart': Timestamp.fromDate(start),
      });
      for (final entry in records.entries) {
        await firestore
            .doc('ulang_growth_records/${entry.key}')
            .set(entry.value);
      }
      await openForm(tester, OperationKind.ulang);
      List<Map<String, dynamic>> plottedWeeks() {
        final chart = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is WeeklyGrowthLinePainter,
          ),
        );
        return (chart.painter! as WeeklyGrowthLinePainter).data;
      }

      // Weeks follow createdAt (like the web), so the two createdAt >= start records with an older observedAt count.
      final weeks = plottedWeeks();
      expect(weeks.map((week) => week['weekNumber']), [1, 2]);
      expect(weeks.first['count'], 5);
      expect(weeks.first['medianWeight'], 30.0);
      expect(weeks.first.containsKey('totalWeight'), isFalse);
      expect(weeks.last['count'], 1);
      expect(weeks.last['medianWeight'], 40.0);
      expect(weeks.last['latestObservation'], nextWeek);

      await tester.runAsync(
        () => firestore.doc('growth_indicators/cycle').update({
          'cycleStart': Timestamp.fromDate(nextWeek),
        }),
      );
      await settle(tester);
      final remaining = plottedWeeks().single;
      expect(remaining['weekNumber'], 1);
      expect(remaining['count'], 1);
      expect(remaining['medianWeight'], 40.0);
      await tester.runAsync(() async {
        for (final entry in records.entries) {
          expect(
            (await firestore.doc('ulang_growth_records/${entry.key}').get())
                .data(),
            entry.value,
          );
        }
        expect(firestore.transactionCalls, 0);
      });
      await close(tester);
    },
  );
  for (final missingStart in [false, true]) {
    testWidgets(
      'growth graph stays empty with only past records (missing admin start: $missingStart)',
      (tester) async {
        final start = DateTime(2026, 10, 10);
        await firestore.doc('growth_indicators/cycle').update({
          'cycleStart': missingStart
              ? FieldValue.delete()
              : Timestamp.fromDate(start),
        });
        await firestore.doc('ulang_growth_records/past').set({
          'createdAt': Timestamp.fromDate(
            start.subtract(const Duration(days: 1)),
          ),
          'weight': 900.0,
        });
        await openForm(tester, OperationKind.ulang);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter is WeeklyGrowthLinePainter,
          ),
          findsNothing,
        );
        expect(
          find.text('Wala pang naitalang lingguhang paglaki'),
          findsOneWidget,
        );
        await close(tester);
      },
    );
  }
  testWidgets(
    'mortality recorded weeks follow the admin cycle without duplicate date ranges',
    (tester) async {
      final yesterday = DateTime(2026, 10, 14, 12);
      final today = DateTime(2026, 10, 15, 12);
      final originals = {
        'yesterday': {
          'deathCount': 1,
          'weekNumber': 99,
          'recordedBy': 'farmer-a',
          'createdAt': Timestamp.fromDate(yesterday),
          'observedAt': Timestamp.fromDate(yesterday),
        },
        'today': {
          'deathCount': 2,
          'weekNumber': 1,
          'recordedBy': 'farmer-a',
          'createdAt': Timestamp.fromDate(today),
          'observedAt': Timestamp.fromDate(today),
        },
      };
      await firestore.doc('growth_indicators/cycle').update({
        'cycleStart': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      for (final entry in originals.entries) {
        await firestore.doc('mortality_records/${entry.key}').set(entry.value);
      }
      await openForm(tester, OperationKind.mortality);
      expect(find.text('Linggo ng cycle: 2'), findsOneWidget);
      expect(find.text('Linggo ng cycle: 3'), findsOneWidget);
      expect(find.textContaining('Linggo ng cycle: 2 ('), findsNothing);
      expect(find.textContaining('Linggo ng cycle: 3 ('), findsNothing);
      expect(find.text('10/14/2026'), findsOneWidget);
      expect(find.text('10/15/2026'), findsOneWidget);

      // A new latest admin parameter document updates the same historical dates.
      await tester.runAsync(() async {
        await firestore.doc('growth_indicators/new-admin-cycle').set({
          'timestamp': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 1)),
          ),
          'cycleStart': Timestamp.fromDate(DateTime(2026, 10, 8)),
          'initialStock': 100,
        });
      });
      await settle(tester);
      expect(find.text('Linggo ng cycle: 1'), findsOneWidget);
      expect(find.text('Linggo ng cycle: 2'), findsOneWidget);
      expect(find.text('Linggo ng cycle: 3'), findsNothing);
      expect(find.text('10/14/2026'), findsOneWidget);
      expect(find.text('10/15/2026'), findsOneWidget);
      await tester.runAsync(() async {
        for (final entry in originals.entries) {
          expect(
            (await firestore.doc('mortality_records/${entry.key}').get())
                .data(),
            entry.value,
          );
        }
        expect((await firestore.collection('logs').get()).docs, isEmpty);
        expect(firestore.transactionCalls, 0);
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      expect(find.text('Linggo ng cycle: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
  testWidgets(
    'mortality recorded weeks follow createdAt at exact boundaries, not observedAt or stored weekNumber',
    (tester) async {
      final start = DateTime(2026, 10, 1);
      final boundary = start.add(const Duration(days: 7));
      await firestore.doc('growth_indicators/cycle').update({
        'cycleStart': Timestamp.fromDate(start),
      });
      await firestore.doc('mortality_records/before-boundary').set({
        'createdAt': Timestamp.fromDate(
          boundary.subtract(const Duration(microseconds: 1)),
        ),
        'deathCount': 1,
        'weekNumber': 42,
      });
      await firestore.doc('mortality_records/at-boundary').set({
        'createdAt': Timestamp.fromDate(boundary.toUtc()),
        'deathCount': 1,
        'weekNumber': 42,
      });
      // createdAt (week 3) wins over an earlier observedAt (week 1).
      await firestore.doc('mortality_records/created-wins').set({
        'createdAt': Timestamp.fromDate(start.add(const Duration(days: 14))),
        'observedAt': Timestamp.fromDate(start),
        'deathCount': 1,
        'weekNumber': 42,
      });
      await openForm(tester, OperationKind.mortality);
      expect(find.text('Linggo ng cycle: 1'), findsOneWidget);
      expect(find.text('Linggo ng cycle: 2'), findsOneWidget);
      expect(find.text('Linggo ng cycle: 3'), findsOneWidget);
      expect(find.text('Linggo: 42'), findsNothing);
      await close(tester);
    },
  );
  for (final noDocument in [false, true]) {
    testWidgets(
      'mortality records are not listed without admin start (no document: $noDocument)',
      (tester) async {
        if (noDocument) {
          await firestore.doc('growth_indicators/cycle').delete();
        } else {
          await firestore.doc('growth_indicators/cycle').update({
            'cycleStart': FieldValue.delete(),
          });
        }
        await firestore.doc('mortality_records/earlier').set({
          'createdAt': Timestamp.now(),
          'deathCount': 1,
          'weekNumber': 99,
        });
        await openForm(tester, OperationKind.mortality);
        // The listener is filtered by cycleStart, so with no cycle nothing is read or listed.
        expect(find.textContaining('Linggo ng cycle'), findsNothing);
        expect(find.text('Linggo: 99'), findsNothing);
        await close(tester);
      },
    );
  }
  testWidgets(
    'mortality created before the admin cycle is not listed',
    (tester) async {
      final start = DateTime(2026, 10, 1);
      await firestore.doc('growth_indicators/cycle').update({
        'cycleStart': Timestamp.fromDate(start),
      });
      for (final entry in {
        'previous-day': start.subtract(const Duration(days: 1)),
        'just-before': start.subtract(const Duration(microseconds: 1)),
        'at-start': start,
      }.entries) {
        await firestore.doc('mortality_records/${entry.key}').set({
          'createdAt': Timestamp.fromDate(entry.value),
          'deathCount': 1,
          'weekNumber': 1,
        });
      }
      await openForm(tester, OperationKind.mortality);
      // createdAt >= cycleStart query: only the at-start record is read.
      expect(find.text('Bago ang kasalukuyang cycle'), findsNothing);
      expect(find.text('Linggo ng cycle: 1'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'mortality without a recording timestamp is not listed',
    (tester) async {
      await firestore.doc('mortality_records/undated').set({
        'createdAt': null,
        'deathCount': 1,
        'weekNumber': 99,
      });
      await openForm(tester, OperationKind.mortality);
      // A null createdAt never matches the createdAt >= cycleStart range filter.
      expect(find.textContaining('Linggo ng cycle'), findsNothing);
      expect(find.text('Linggo: 99'), findsNothing);
      await close(tester);
    },
  );
  testWidgets(
    'four single-death entries in one week save separate cards and update survival',
    (tester) async {
      await openForm(tester, OperationKind.mortality);
      expect(find.text('Bilang ng namatay sa talang ito'), findsOneWidget);
      for (var count = 1; count <= 4; count++) {
        await tester.enterText(find.byType(TextField).at(2), '1');
        await submit(tester, OperationKind.mortality);
        expect(find.textContaining('Matagumpay na na-save'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).at(2))
              .controller!
              .text,
          isEmpty,
        );
        await tester.runAsync(() async {
          final records =
              (await firestore.collection('mortality_records').get()).docs;
          final logs = (await firestore.collection('logs').get()).docs;
          expect(records, hasLength(count));
          expect(logs, hasLength(count));
          expect(
            records.map((d) => d.id),
            unorderedEquals(logs.map((d) => d.id)),
          );
          expect(records.every((d) => d.data()['deathCount'] == 1), isTrue);
          expect(records.every((d) => d.data()['weekNumber'] == 1), isTrue);
          expect(
            (await firestore.doc('growth_indicators/cycle').get())
                .data()!['survivalRate'],
            100 - count,
          );
        });
      }
      expect(find.text('Namatay: 1'), findsNWidgets(3));
      final more = find.text('See More (+1)');
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Namatay: 1'), findsNWidgets(4));
      await close(tester);
    },
  );
  testWidgets(
    'mortality can be recorded again after server mortality records are reset',
    (tester) async {
      await openForm(tester, OperationKind.mortality);
      await submit(tester, OperationKind.mortality);
      expect(find.textContaining('Matagumpay na na-save'), findsOneWidget);
      await tester.runAsync(() async {
        final records = await firestore.collection('mortality_records').get();
        expect(records.docs, hasLength(1));
        await records.docs.single.reference.delete();
        // Historical logs remain on the server after this reset.
        expect((await firestore.collection('logs').get()).docs, hasLength(1));
      });
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(2), '4');
      await submit(tester, OperationKind.mortality);
      expect(find.textContaining('Matagumpay na na-save'), findsOneWidget);
      await tester.runAsync(() async {
        final records = await firestore.collection('mortality_records').get();
        expect(records.docs, hasLength(1));
        expect(records.docs.single.data()['deathCount'], 4);
        expect((await firestore.collection('logs').get()).docs, hasLength(2));
        expect(
          (await firestore.doc('growth_indicators/cycle').get())
              .data()!['survivalRate'],
          96,
        );
      });
      // Another death in the same week creates its own entry.
      await tester.enterText(find.byType(TextField).at(2), '3');
      await submit(tester, OperationKind.mortality);
      expect(find.textContaining('Matagumpay na na-save'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        isEmpty,
      );
      await tester.runAsync(() async {
        expect(
          (await firestore.collection('mortality_records').get()).docs,
          hasLength(2),
        );
        expect((await firestore.collection('logs').get()).docs, hasLength(3));
        expect(
          (await firestore.doc('growth_indicators/cycle').get())
              .data()!['survivalRate'],
          93,
        );
      });
      await close(tester);
    },
  );
  testWidgets(
    'summary rejection clears confirmed form and explains saved record',
    (tester) async {
      firestore.failTransactionNumber = 2;
      await openForm(tester, OperationKind.ulang);
      await submit(tester, OperationKind.ulang);
      expect(find.textContaining('record was saved, but'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.runAsync(() async {
        expect((await firestore.collection('logs').get()).docs, hasLength(1));
        expect(
          (await firestore.collection('ulang_growth_records').get()).docs,
          hasLength(1),
        );
      });
      await settle(tester);
      expect(firestore.transactionCalls, 2);
      await close(tester);
    },
  );
  testWidgets('timed-out check cannot save when its late reply arrives', (
    tester,
  ) async {
    auth.gate = Completer<void>();
    await openForm(tester, OperationKind.ulang);
    await submit(tester, OperationKind.ulang);
    await tester.pump(const Duration(seconds: 12));
    await settle(tester);
    expectValues(tester, OperationKind.ulang);
    expect(find.text('Internet connection is required.'), findsOneWidget);
    auth.gate!.complete();
    await settle(tester);
    await expectNothingRecorded(tester);
    await close(tester);
  });
}

class _TransactionFirestore extends FakeFirebaseFirestore {
  int transactionCalls = 0;
  Object? transactionError;
  Completer<void>? acknowledgmentGate;
  int? failTransactionNumber;
  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactionCalls++;
    if (transactionError != null || transactionCalls == failTransactionNumber) {
      return Future<T>.error(
        transactionError ??
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
      );
    }
    final result = await super.runTransaction(
      (tx) => handler(_OwnerLogTransaction(tx)),
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    if (acknowledgmentGate != null) await acknowledgmentGate!.future;
    return result;
  }
}

/// Models the owner-only log rule that rejects reads of nonexistent logs.
/// FakeFirebaseFirestore itself does not evaluate resource.data conditions.
class _OwnerLogTransaction implements Transaction {
  _OwnerLogTransaction(this.delegate);
  final Transaction delegate;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    final snapshot = await delegate.get(ref);
    if (ref.parent.path == 'logs' && !snapshot.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'A missing log has no ownership fields to authorize its read.',
      );
    }
    return snapshot;
  }

  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) =>
      delegate.set(ref, data, options);

  @override
  Transaction update(DocumentReference ref, Map<String, dynamic> data) =>
      delegate.update(ref, data);

  @override
  Transaction delete(DocumentReference ref) => delegate.delete(ref);
}
