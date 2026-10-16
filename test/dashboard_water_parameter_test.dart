// Transport doubles exercise the installed FlutterFire SDK and real dashboard.
// ignore_for_file: depend_on_referenced_packages, implementation_imports
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show FieldPath;
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart'
    as pigeon;
import 'package:cloud_firestore_platform_interface/src/method_channel/utils/firestore_message_codec.dart';
import 'package:demo_1_langto/landing_page.dart';
import 'package:demo_1_langto/notification_service.dart';
import 'package:demo_1_langto/water_parameter_badge.dart';
import 'package:demo_1_langto/water_parameter_status.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FirestoreTransport transport;
  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    FirebaseAuthPlatform.instance = _NoUserAuth();
    // Flutter widget tests do not load the Material icon font automatically.
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async => call.method == 'initialize' ? true : null,
        );
    await NotificationService.instance.initialize();
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    transport = _FirestoreTransport()..install();
  });
  tearDown(() => transport.dispose());

  WaterParameterStatus? badge(WidgetTester tester, WaterParameter parameter) =>
      tester
          .widget<WaterParameterBadge>(find.byKey(ValueKey(parameter)))
          .status;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const RepaintBoundary(
        key: Key('dashboard_capture'),
        child: MaterialApp(home: DashboardPage()),
      ),
    );
    await tester.pumpAndSettle();
    await transport.document('Aquaponics/Ulang', {
      'statistics': {
        'phValue': {'average': 8.2},
        'waterTemperatureC': {'average': 28},
        'oxygenLevelMgL': {'average': 6},
        'salinityPpt': {'average': 1},
        'tdsPpm': {'average': 3852},
        'turbidityNTU': {'average': 10},
      },
    });
    await tester.pumpAndSettle();
  }

  String? value(WidgetTester tester, WaterParameter parameter) => tester
      .widget<Text>(find.byKey(ValueKey('water_value_${parameter.name}')))
      .data;

  testWidgets(
    'TDS and salinity show independent admin-source readings and labels',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {
        'tds_min': 1000,
        'tds_max': 3000,
      });
      await tester.pumpAndSettle();
      expect(value(tester, WaterParameter.tds), '3852 ppm');
      expect(value(tester, WaterParameter.salinity), '1.00 ppt');
      expect(badge(tester, WaterParameter.tds), WaterParameterStatus.critical);
      expect(
        badge(tester, WaterParameter.salinity),
        WaterParameterStatus.optimal,
      );
      expect(find.text('TDS'), findsOneWidget);
      expect(find.text('Salinity'), findsOneWidget);
      expect(find.text('Salinity / TDS'), findsNothing);
      expect(
        transport.paths.where((path) => path == 'Aquaponics/Ulang').length,
        1,
      );
      await transport.document('Aquaponics/Ulang', {
        'statistics': {
          'tdsPpm': {'average': 5200.6},
          'salinityPpt': {'average': 2.34},
        },
      });
      await tester.pumpAndSettle();
      expect(value(tester, WaterParameter.tds), '5201 ppm');
      expect(value(tester, WaterParameter.salinity), '2.34 ppt');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing TDS is NO DATA while salinity still shows its own value',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {});
      await transport.document('Aquaponics/Ulang', {
        'statistics': {
          'salinityPpt': {'average': 1.23},
        },
      });
      await tester.pumpAndSettle();
      expect(value(tester, WaterParameter.tds), '--');
      expect(badge(tester, WaterParameter.tds), WaterParameterStatus.noData);
      expect(value(tester, WaterParameter.salinity), '1.23 ppt');
      expect(
        badge(tester, WaterParameter.salinity),
        WaterParameterStatus.optimal,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a TDS-only server change updates the card and refresh feedback',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {});
      await tester.pumpAndSettle();
      final sensor = Map<String, Object?>.from(transport.getSensor!);
      final stats = Map<String, Object?>.from(sensor['statistics']! as Map);
      stats['tdsPpm'] = {'average': 4500.6};
      sensor['statistics'] = stats;
      transport.getSensor = sensor;
      transport.getSettings = {};
      await tester
          .widget<RefreshIndicator>(
            find.byKey(const Key('dashboard_refresh_indicator')),
          )
          .onRefresh();
      await tester.pumpAndSettle();
      expect(value(tester, WaterParameter.tds), '4501 ppm');
      expect(value(tester, WaterParameter.salinity), '1.00 ppt');
      expect(
        find.text('Dashboard refreshed with new sensor data.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'phone layout pairs TDS/salinity and turbidity/temperature without overflow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 360.0, 390.0]) {
        tester.view.physicalSize = Size(width, 844);
        await open(tester);
        await transport.document('settings/thresholds', {
          'tds_max': 3000,
          'ph_max': 8,
        });
        await tester.pumpAndSettle();
        final tds = tester.getRect(
          find.byKey(const ValueKey(WaterParameter.tds)),
        );
        final salinity = tester.getRect(
          find.byKey(const ValueKey(WaterParameter.salinity)),
        );
        final turbidity = tester.getRect(
          find.byKey(const ValueKey(WaterParameter.turbidity)),
        );
        final temperature = tester.getRect(
          find.byKey(const ValueKey(WaterParameter.temperature)),
        );
        expect(tds.left, lessThan(salinity.left));
        expect(tds.top, closeTo(salinity.top, 0.1));
        expect(turbidity.left, lessThan(temperature.left));
        expect(turbidity.top, closeTo(temperature.top, 0.1));
        expect(tds.bottom, lessThan(turbidity.top));
        expect(tester.takeException(), isNull, reason: 'phone width $width');
        if (width == 390) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('dashboard_capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/tds-salinity-validation')
              ..createSync(recursive: true);
            File(
              '${directory.path}/dashboard-phone.png',
            ).writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('global Firebase thresholds update every real dashboard badge', (
    tester,
  ) async {
    await open(tester);
    for (final parameter in WaterParameter.values) {
      expect(badge(tester, parameter), isNull); // No guessed label during load.
    }
    await transport.document('settings/thresholds', {});
    await tester.pumpAndSettle();
    for (final parameter in WaterParameter.values) {
      expect(badge(tester, parameter), WaterParameterStatus.optimal);
    }
    await transport.document('settings/thresholds', {
      'ph_max': 8,
      'temp_max': 28,
      'o2_min': 8,
      'salinity_max': 0.5,
      'turbidity_max': 5,
      'tds_min': 1000,
      'tds_max': 3000,
    });
    await tester.pumpAndSettle();
    expect(badge(tester, WaterParameter.ph), WaterParameterStatus.warning);
    expect(
      badge(tester, WaterParameter.temperature),
      WaterParameterStatus.warning,
    );
    expect(badge(tester, WaterParameter.oxygen), WaterParameterStatus.warning);
    expect(
      badge(tester, WaterParameter.salinity),
      WaterParameterStatus.critical,
    );
    expect(
      badge(tester, WaterParameter.turbidity),
      WaterParameterStatus.critical,
    );
    expect(badge(tester, WaterParameter.tds), WaterParameterStatus.critical);
    expect(transport.paths, contains('settings/thresholds'));
    expect(transport.paths.any((path) => path.startsWith('farms/')), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(transport.cancelledDocuments, contains('settings/thresholds'));
  });

  testWidgets('unconfirmed cached thresholds cannot classify new readings', (
    tester,
  ) async {
    await open(tester);
    await transport.document('settings/thresholds', {
      'ph_max': 7,
    }, cached: true);
    await tester.pumpAndSettle();
    expect(badge(tester, WaterParameter.ph), isNull);
    await transport.document('settings/thresholds', {'ph_max': 7});
    await tester.pumpAndSettle();
    expect(badge(tester, WaterParameter.ph), WaterParameterStatus.critical);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'missing settings use admin defaults; missing sensors show NO DATA',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', null);
      await tester.pumpAndSettle();
      expect(badge(tester, WaterParameter.ph), WaterParameterStatus.optimal);
      await transport.document('Aquaponics/Ulang', {'statistics': {}});
      await tester.pumpAndSettle();
      for (final parameter in WaterParameter.values) {
        expect(badge(tester, parameter), WaterParameterStatus.noData);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'old alerts cannot override current salinity and turbidity labels or values',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {});
      await transport.alerts([
        {'title': 'High salinity', 'message': 'Current: 42 ppt'},
        {'title': 'High turbidity', 'message': 'Current: 600 NTU'},
      ]);
      await tester.pumpAndSettle();
      expect(
        badge(tester, WaterParameter.salinity),
        WaterParameterStatus.optimal,
      );
      expect(
        badge(tester, WaterParameter.turbidity),
        WaterParameterStatus.optimal,
      );
      expect(find.text('1.00 ppt'), findsOneWidget);
      expect(find.text('10 NTU'), findsOneWidget);
      expect(find.text('42 ppt'), findsNothing);
      expect(find.text('600 NTU'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pull refresh fetches the global admin configuration from the server',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {});
      await tester.pumpAndSettle();
      expect(badge(tester, WaterParameter.ph), WaterParameterStatus.optimal);
      transport.getSettings = {'ph_max': 7};
      await tester
          .widget<RefreshIndicator>(
            find.byKey(const Key('dashboard_refresh_indicator')),
          )
          .onRefresh();
      await tester.pumpAndSettle();
      expect(badge(tester, WaterParameter.ph), WaterParameterStatus.critical);
      expect(transport.settingsGets, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a delayed refresh cannot replace a newer live threshold update',
    (tester) async {
      await open(tester);
      await transport.document('settings/thresholds', {});
      await tester.pumpAndSettle();
      transport.getSettings = {'ph_max': 7};
      transport.settingsGetGate = Completer<void>();
      final refreshed = tester
          .widget<RefreshIndicator>(
            find.byKey(const Key('dashboard_refresh_indicator')),
          )
          .onRefresh();
      await tester.pump();
      expect(transport.settingsGets, 1);
      await transport.document('settings/thresholds', {'ph_max': 8.5});
      await tester.pump();
      expect(badge(tester, WaterParameter.ph), WaterParameterStatus.optimal);
      transport.settingsGetGate!.complete();
      await refreshed;
      await tester.pumpAndSettle();
      expect(badge(tester, WaterParameter.ph), WaterParameterStatus.optimal);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

class _NoUserAuth extends FirebaseAuthPlatform {
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({
    String? languageCode,
    PigeonUserDetails? currentUser,
  }) => this;
  @override
  UserPlatform? get currentUser => null;
}

class _FirestoreTransport {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final paths = <String>[];
  final cancelledDocuments = <String>[];
  final documentChannels = <String, String>{};
  final alertChannels = <String>[];
  final methodChannels = <MethodChannel>[];
  static const prefix =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.';
  static const eventCodec = StandardMethodCodec(FirestoreMessageCodec());
  var sequence = 0;
  int settingsGets = 0;
  Map<String, Object?>? getSettings;
  Map<String, Object?>? getSensor;
  Completer<void>? settingsGetGate;

  BasicMessageChannel<Object?> host(String method) =>
      BasicMessageChannel('$prefix$method', const _HostTestCodec());

  void install() {
    messenger.setMockDecodedMessageHandler<Object?>(
      host('documentReferenceSnapshot'),
      (message) async {
        final request = (message as List)[1] as pigeon.DocumentReferenceRequest;
        paths.add(request.path);
        final id = 'water-test-${sequence++}';
        final name = 'plugins.flutter.io/firebase_firestore/document/$id';
        documentChannels[request.path] = name;
        final channel = MethodChannel(name, eventCodec);
        methodChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'cancel') cancelledDocuments.add(request.path);
          return null;
        });
        return [id];
      },
    );
    messenger.setMockDecodedMessageHandler<Object?>(host('querySnapshot'), (
      message,
    ) async {
      final id = 'water-test-${sequence++}';
      final channel = MethodChannel(
        'plugins.flutter.io/firebase_firestore/query/$id',
        eventCodec,
      );
      methodChannels.add(channel);
      if ((message as List)[1] == 'alerts') alertChannels.add(channel.name);
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listen') {
          final empty = pigeon.PigeonQuerySnapshot(
            documents: [],
            documentChanges: [],
            metadata: pigeon.PigeonSnapshotMetadata(
              isFromCache: false,
              hasPendingWrites: false,
            ),
          );
          messenger.handlePlatformMessage(
            channel.name,
            eventCodec.encodeSuccessEnvelope(empty.encode()),
            (_) {},
          );
        }
        return null;
      });
      return [id];
    });
    messenger.setMockDecodedMessageHandler<Object?>(
      host('documentReferenceGet'),
      (message) async {
        final request = (message as List)[1] as pigeon.DocumentReferenceRequest;
        if (request.path == 'settings/thresholds') settingsGets++;
        final data = request.path == 'settings/thresholds'
            ? getSettings
            : getSensor;
        if (request.path == 'settings/thresholds') {
          await settingsGetGate?.future;
        }
        return [
          pigeon.PigeonDocumentSnapshot(
            path: request.path,
            data: data,
            metadata: pigeon.PigeonSnapshotMetadata(
              isFromCache: false,
              hasPendingWrites: false,
            ),
          ),
        ];
      },
    );
    messenger.setMockDecodedMessageHandler<Object?>(
      host('queryGet'),
      (_) async => [
        pigeon.PigeonQuerySnapshot(
          documents: [],
          documentChanges: [],
          metadata: pigeon.PigeonSnapshotMetadata(
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      ],
    );
  }

  Future<void> alerts(List<Map<String, Object?>> values) async {
    final metadata = pigeon.PigeonSnapshotMetadata(
      isFromCache: false,
      hasPendingWrites: false,
    );
    final documents = [
      for (var i = 0; i < values.length; i++)
        pigeon.PigeonDocumentSnapshot(
          path: 'alerts/old-$i',
          data: values[i],
          metadata: metadata,
        ).encode(),
    ];
    for (final name in alertChannels) {
      final done = Completer<void>();
      messenger.handlePlatformMessage(
        name,
        eventCodec.encodeSuccessEnvelope([documents, [], metadata.encode()]),
        (_) => done.complete(),
      );
      await done.future;
    }
  }

  Future<void> document(
    String path,
    Map<String, Object?>? data, {
    bool cached = false,
  }) async {
    if (path == 'Aquaponics/Ulang') getSensor = data;
    final event = pigeon.PigeonDocumentSnapshot(
      path: path,
      data: data,
      metadata: pigeon.PigeonSnapshotMetadata(
        isFromCache: cached,
        hasPendingWrites: false,
      ),
    );
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      documentChannels[path]!,
      eventCodec.encodeSuccessEnvelope(event.encode()),
      (_) => done.complete(),
    );
    await done.future;
  }

  void dispose() {
    for (final method in [
      'documentReferenceSnapshot',
      'querySnapshot',
      'documentReferenceGet',
      'queryGet',
    ]) {
      messenger.setMockDecodedMessageHandler<Object?>(host(method), null);
    }
    for (final channel in methodChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

// Native Firestore decodes query FieldPaths. The Dart SDK intentionally leaves
// that host-only decoding out of its codec, so the transport double supplies it.
class _HostTestCodec extends FirestoreMessageCodec {
  const _HostTestCodec();
  @override
  void writeValue(WriteBuffer buffer, dynamic value) =>
      (pigeon.FirebaseFirestoreHostApi.codec as StandardMessageCodec)
          .writeValue(buffer, value);
  @override
  Object? readValueOfType(int type, ReadBuffer buffer) => switch (type) {
    130 => pigeon.DocumentReferenceRequest.decode(readValue(buffer)!),
    131 => pigeon.FirestorePigeonFirebaseApp.decode(readValue(buffer)!),
    134 => pigeon.PigeonDocumentSnapshot.decode(readValue(buffer)!),
    135 => pigeon.PigeonFirebaseSettings.decode(readValue(buffer)!),
    136 => pigeon.PigeonGetOptions.decode(readValue(buffer)!),
    137 => pigeon.PigeonQueryParameters.decode(readValue(buffer)!),
    138 => pigeon.PigeonQuerySnapshot.decode(readValue(buffer)!),
    192 => FieldPath(
      List.generate(readSize(buffer), (_) => readValue(buffer)! as String),
    ),
    _ => super.readValueOfType(type, buffer),
  };
}
