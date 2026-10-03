// Used only when creating an account, not to validate existing credentials.
String? validateNewPassword(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Enter your password.';
  }
  if (value.runes.length < 8) {
    return 'Use at least 8 characters.';
  }

  // Normalize only for comparison. The password sent to Firebase stays intact.
  final lowercase = value.trim().toLowerCase();
  final comparison = lowercase.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final withoutNumberSuffix = comparison.replaceFirst(RegExp(r'\d+$'), '');
  if (lowercase.runes.toSet().length == 1 ||
      _commonPasswords.contains(comparison) ||
      _commonPasswords.contains(withoutNumberSuffix)) {
    return 'This password is too common. Choose a different one.';
  }
  return null;
}

const _commonPasswords = <String>{
  'admin',
  'administrator',
  'password',
  'passw0rd',
  'qwerty',
  'qwertyui',
  'qwertyuiop',
  'asdfghjk',
  'asdfghjkl',
  'zxcvbnm',
  'letmein',
  'welcome',
  'changeme',
  'default',
  'guest',
  'test',
  'testing',
  'user',
  'username',
  'login',
  'iloveyou',
  'monkey',
  'dragon',
  'sunshine',
  'princess',
  'football',
  'baseball',
  'abcdefgh',
  'abcd',
  'abc',
  'bantayulang',
  '1q2w3e4r',
  '1qaz2wsx',
  '01234567',
  '0123456789',
  '12345678',
  '123456789',
  '1234567890',
  '23456789',
  '34567890',
  '87654321',
  '98765432',
  '987654321',
  '0987654321',
  '12341234',
  '12121212',
};
