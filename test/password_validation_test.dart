import 'package:demo_1_langto/password_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires a password', () {
    for (final password in [null, '', '        ']) {
      expect(validateNewPassword(password), 'Enter your password.');
    }
  });

  test('requires eight characters, an uppercase letter, and a number', () {
    const cases = {
      'River73': '\u2022 Use at least 8 characters.',
      'river739': '\u2022 Include one uppercase letter.',
      'Riverbed': '\u2022 Include one number.',
      '73918264': '\u2022 Include one uppercase letter.',
      'riverbed!': '\u2022 Include one uppercase letter.\n\u2022 Include one number.',
      'river': '\u2022 Use at least 8 characters.\n\u2022 Include one uppercase letter.\n\u2022 Include one number.',
    };
    for (final entry in cases.entries) {
      expect(validateNewPassword(entry.key), entry.value);
    }
  });

  test('accepts compliant passwords without requiring a special character', () {
    for (final password in ['River739', 'River739!', 'RIVER739']) {
      expect(validateNewPassword(password), isNull);
    }
  });

  test('preserves the existing common-password rejection', () {
    for (final password in ['Password1', 'Admin123', 'Bantayulang739!']) {
      expect(
        validateNewPassword(password),
        '\u2022 This password is too common. Choose a different one.',
      );
    }
  });
}
