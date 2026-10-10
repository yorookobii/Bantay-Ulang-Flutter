import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:demo_1_langto/signup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _TestUser user;
  late _TestAuth auth;
  late _TestProfile profile;
  late _TestFirestore firestore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    user = _TestUser();
    auth = _TestAuth(user);
    profile = _TestProfile();
    firestore = _TestFirestore(profile);
  });

  Future<void> showAuth(WidgetTester tester, {bool resend = false}) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SignupPage(
          auth: auth,
          firestore: firestore,
          initialMessage: resend ? 'Please verify your email.' : null,
          showResendOption: resend,
        ),
        routes: {
          '/dashboard': (_) =>
              const Scaffold(body: Text('Protected dashboard')),
        },
      ),
    );
    await tester.pump();
  }

  Future<void> enterLogin(WidgetTester tester) async {
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'user@example.com',
    );
    // Existing passwords must not be rejected by the new-account policy.
    await tester.enterText(find.byType(TextFormField).at(1), 'old');
  }

  Future<void> finish(WidgetTester tester) async {
    // Allow chained SDK futures and the subsequent route transition to finish.
    // pumpAndSettle is unsuitable while the auth background animation repeats.
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> login(WidgetTester tester) async {
    await enterLogin(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
    await finish(tester);
  }

  Future<void> register(WidgetTester tester) async {
    await tester.tap(find.text('Create an Account').first);
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Farm User');
    await tester.enterText(fields.at(1), 'user@example.com');
    await tester.enterText(fields.at(2), 'River garden 739!');
    await tester.enterText(fields.at(3), 'River garden 739!');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create an Account'));
    await finish(tester);
  }

  void expectNoSession() {
    expect(auth.currentUser, isNull);
    expect(auth.signOutCalls, 1);
    expect(find.text('Protected dashboard'), findsNothing);
  }

  testWidgets('a profile read failure signs out before re-enabling the form', (
    tester,
  ) async {
    profile.readError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );
    auth.signOutGate = Completer<void>();
    await showAuth(tester);
    await login(tester);

    expect(auth.signOutCalls, 1);
    expect(auth.currentUser, same(user));
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    auth.signOutGate!.complete();
    await finish(tester);

    expectNoSession();
    expect(
      find.text('Unable to log in right now. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a reload failure closes the authenticated session', (
    tester,
  ) async {
    user.reloadError = FirebaseAuthException(code: 'user-disabled');
    await showAuth(tester);
    await login(tester);
    expectNoSession();
  });

  testWidgets('a verification flag write failure closes the session', (
    tester,
  ) async {
    profile.data!['emailVerified'] = false;
    profile.writeError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await showAuth(tester);
    await login(tester);
    expectNoSession();
    expect(profile.updates, [
      {'emailVerified': true},
    ]);
  });

  for (final rejection in [
    'pending',
    'suspended',
    'admin',
    'technician',
    'unverified',
    'missing profile',
  ]) {
    testWidgets('$rejection accounts cannot retain a login session', (
      tester,
    ) async {
      switch (rejection) {
        case 'pending':
        case 'suspended':
          profile.data!['status'] = rejection;
        case 'admin':
        case 'technician':
          profile.data!['role'] = rejection;
        case 'unverified':
          user.verified = false;
        case 'missing profile':
          profile.data = null;
      }
      await showAuth(tester);
      await login(tester);
      expectNoSession();
      if (rejection == 'unverified') {
        expect(find.text('Resend verification email'), findsOneWidget);
      }
      if (rejection == 'missing profile') {
        expect(
          find.textContaining('account setup is incomplete'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'an approved verified user keeps the session and reaches the dashboard',
    (tester) async {
      await showAuth(tester);
      await login(tester);
      expect(find.text('Protected dashboard'), findsOneWidget);
      expect(auth.currentUser, same(user));
      expect(auth.signOutCalls, 0);
      expect(auth.lastPassword, 'old');
      expect(auth.signInCalls, 1);
      expect(profile.readCalls, 1);
      expect(profile.updates, isEmpty);
    },
  );

  testWidgets('rapid repeated submit callbacks start only one sign-in', (
    tester,
  ) async {
    auth.signInGate = Completer<void>();
    await showAuth(tester);
    await enterLogin(tester);
    final submit = find.widgetWithText(ElevatedButton, 'Log in');
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(auth.signInCalls, 1);
    auth.signInGate!.complete();
    await finish(tester);
    expect(find.text('Protected dashboard'), findsOneWidget);
  });

  testWidgets('closing the page during sign-in does not leave a session', (
    tester,
  ) async {
    auth.signInGate = Completer<void>();
    await showAuth(tester);
    await login(tester);
    await tester.pumpWidget(const SizedBox());
    auth.signInGate!.complete();
    await finish(tester);
    expectNoSession();
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid signup submissions create only one account', (
    tester,
  ) async {
    auth.createGate = Completer<void>();
    await showAuth(tester);
    await tester.tap(find.text('Create an Account').first);
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Farm User');
    await tester.enterText(fields.at(1), 'user@example.com');
    await tester.enterText(fields.at(2), 'River garden 739!');
    await tester.enterText(fields.at(3), 'River garden 739!');
    final submit = find.widgetWithText(ElevatedButton, 'Create an Account');
    await tester.tap(submit);
    await tester.tap(submit);
    expect(auth.createCalls, 1);
    auth.createGate!.complete();
    await finish(tester);
    expectNoSession();
    expect(user.verificationCalls, 1);
  });

  testWidgets('rapid verification resends use only one temporary session', (
    tester,
  ) async {
    auth.signInGate = Completer<void>();
    await showAuth(tester, resend: true);
    await enterLogin(tester);
    final resend = find.text('Resend verification email');
    await tester.tap(resend);
    await tester.tap(resend);
    expect(auth.signInCalls, 1);
    auth.signInGate!.complete();
    await finish(tester);
    expectNoSession();
    expect(user.verificationCalls, 1);
    expect(auth.lastPassword, 'old');
  });

  testWidgets('a saved lockout blocks login and verification resend', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'login_failed_attempts': 3,
      'login_lockout_until': DateTime.now()
          .add(const Duration(minutes: 3))
          .millisecondsSinceEpoch,
    });
    await showAuth(tester, resend: true);
    await enterLogin(tester);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Resend verification email'));
    await finish(tester);
    expect(auth.signInCalls, 0);
    expect(user.verificationCalls, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an expired saved lockout starts a fresh attempt count', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'login_failed_attempts': 3,
      'login_lockout_until': DateTime.now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch,
    });
    auth.signInError = FirebaseAuthException(code: 'invalid-credential');
    await showAuth(tester);
    await login(tester);
    expect(find.textContaining('2 tries left'), findsOneWidget);
    expect(
      (await SharedPreferences.getInstance()).getInt('login_failed_attempts'),
      1,
    );
  });

  testWidgets('three invalid credentials still trigger the existing lockout', (
    tester,
  ) async {
    auth.signInError = FirebaseAuthException(code: 'invalid-credential');
    await showAuth(tester);
    for (var attempt = 0; attempt < 3; attempt++) {
      await login(tester);
    }
    expect(auth.signInCalls, 3);
    expect(find.textContaining('Too many login attempts.'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signup preserves pending user fields and signs out', (
    tester,
  ) async {
    await showAuth(tester);
    await register(tester);
    expectNoSession();
    expect(auth.createCalls, 1);
    expect(user.verificationCalls, 1);
    expect(profile.data, {
      'email': 'user@example.com',
      'fullName': 'Farm User',
      'role': 'user',
      'status': 'pending',
      'emailVerified': false,
      'createdAt': isA<FieldValue>(),
    });
    expect(
      find.textContaining('Account created. Check your email'),
      findsOneWidget,
    );
  });

  testWidgets(
    'verification delivery failure leaves a pending profile and supports resend',
    (tester) async {
      user.verificationError = FirebaseAuthException(code: 'too-many-requests');
      await showAuth(tester);
      await register(tester);
      expectNoSession();
      expect(profile.data!['status'], 'pending');
      expect(profile.data!['emailVerified'], false);
      expect(
        find.textContaining(
          'Your account was created, but the verification email',
        ),
        findsOneWidget,
      );

      user.verificationError = null;
      await tester.tap(find.text('Resend verification email'));
      await finish(tester);
      expect(auth.currentUser, isNull);
      expect(auth.signOutCalls, 2);
      expect(auth.createCalls, 1);
      expect(auth.signInCalls, 1);
      expect(user.verificationCalls, 2);
      expect(
        find.text('Verification email sent. Check your inbox for the link.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'profile creation failure reports incomplete setup and signs out',
    (tester) async {
      profile.data = null;
      profile.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      await showAuth(tester);
      await register(tester);
      expectNoSession();
      expect(profile.data, isNull);
      expect(user.verificationCalls, 0);
      expect(
        find.textContaining('profile setup could not be completed'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'account creation failure performs cleanup without creating a profile',
    (tester) async {
      profile.data = null;
      auth.createError = FirebaseAuthException(code: 'email-already-in-use');
      await showAuth(tester);
      await register(tester);
      expectNoSession();
      expect(profile.data, isNull);
      expect(user.verificationCalls, 0);
    },
  );

  for (final error in [
    FirebaseAuthException(code: 'too-many-requests'),
    StateError('mail unavailable'),
  ]) {
    testWidgets('resend failure cleans up (${error.runtimeType})', (
      tester,
    ) async {
      user.verificationError = error;
      await showAuth(tester, resend: true);
      await enterLogin(tester);
      await tester.tap(find.text('Resend verification email'));
      await finish(tester);
      expectNoSession();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('signup can finish and sign out after the page is closed', (
    tester,
  ) async {
    auth.createGate = Completer<void>();
    await showAuth(tester);
    await register(tester);
    await tester.pumpWidget(const SizedBox());
    auth.createGate!.complete();
    await finish(tester);
    expectNoSession();
    expect(profile.data!['fullName'], 'Farm User');
    expect(user.verificationCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sign-out failure is surfaced without dashboard navigation', (
    tester,
  ) async {
    profile.data!['status'] = 'pending';
    auth.signOutError = StateError('native sign-out failed');
    await showAuth(tester);
    await login(tester);
    expect(
      find.textContaining('Unable to finish signing out.'),
      findsOneWidget,
    );
    expect(find.text('Protected dashboard'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unexpected password reset errors release the form', (
    tester,
  ) async {
    auth.resetError = StateError('reset unavailable');
    await showAuth(tester);
    await enterLogin(tester);
    await tester.tap(find.text('Forgot Password?'));
    await finish(tester);
    expect(
      find.textContaining('Unable to send the password reset email'),
      findsOneWidget,
    );
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
    expect(auth.signInCalls, 0);
    expect(auth.currentUser, isNull);
  });
}

class _TestDouble {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _TestUser extends _TestDouble implements User {
  bool verified = true;
  Object? reloadError;
  Object? verificationError;
  int verificationCalls = 0;

  @override
  String get uid => 'test-user';
  @override
  bool get emailVerified => verified;

  @override
  Future<void> reload() async {
    if (reloadError != null) throw reloadError!;
  }

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    verificationCalls++;
    if (verificationError != null) throw verificationError!;
  }
}

class _TestCredential extends _TestDouble implements UserCredential {
  _TestCredential(this.user);
  @override
  final User user;
}

class _TestAuth extends _TestDouble implements FirebaseAuth {
  _TestAuth(this.user);
  final _TestUser user;
  User? _currentUser;
  Object? signInError;
  Object? createError;
  Object? signOutError;
  Object? resetError;
  Completer<void>? signInGate;
  Completer<void>? createGate;
  Completer<void>? signOutGate;
  int signInCalls = 0;
  int createCalls = 0;
  int signOutCalls = 0;
  String? lastPassword;

  @override
  User? get currentUser => _currentUser;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    lastPassword = password;
    if (signInGate != null) await signInGate!.future;
    if (signInError != null) throw signInError!;
    _currentUser = user;
    return _TestCredential(user);
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    createCalls++;
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    _currentUser = user;
    return _TestCredential(user);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutGate != null) await signOutGate!.future;
    if (signOutError != null) throw signOutError!;
    _currentUser = null;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (resetError != null) throw resetError!;
  }
}

class _TestFirestore extends _TestDouble implements FirebaseFirestore {
  _TestFirestore(this.profile);
  final _TestProfile profile;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    expect(collectionPath, 'users');
    return _TestUsers(profile);
  }
}

// These test-only Firestore doubles deliberately simulate SDK failure paths.
// ignore: subtype_of_sealed_class
class _TestUsers extends _TestDouble
    implements CollectionReference<Map<String, dynamic>> {
  _TestUsers(this.profile);
  final _TestProfile profile;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    expect(path, 'test-user');
    return profile;
  }
}

// ignore: subtype_of_sealed_class, must_be_immutable
class _TestProfile extends _TestDouble
    implements DocumentReference<Map<String, dynamic>> {
  Map<String, dynamic>? data = {
    'role': 'user',
    'status': 'active',
    'emailVerified': true,
  };
  Object? readError;
  Object? writeError;
  int readCalls = 0;
  final updates = <Map<Object, Object?>>[];

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    readCalls++;
    if (readError != null) throw readError!;
    return _TestSnapshot(this);
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (writeError != null) throw writeError!;
    this.data = Map.of(data);
  }

  @override
  Future<void> update(Map<Object, Object?> data) async {
    updates.add(Map.of(data));
    if (writeError != null) throw writeError!;
    this.data!.addAll(Map<String, dynamic>.from(data));
  }
}

// ignore: subtype_of_sealed_class
class _TestSnapshot extends _TestDouble
    implements DocumentSnapshot<Map<String, dynamic>> {
  _TestSnapshot(this.reference);
  @override
  final _TestProfile reference;
  @override
  bool get exists => reference.data != null;
  @override
  Map<String, dynamic>? data() =>
      reference.data == null ? null : Map.of(reference.data!);
}
