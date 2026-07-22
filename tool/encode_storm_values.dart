// Credential encoder for the relay layer.
//
// Fill the plaintext map below, then run:
//   dart run tool/encode_storm_values.dart
//
// Paste the printed byte arrays into:
//   lib/relay/config/relay_endpoints.dart   (configEndpoint, gcdBase)
//   lib/relay/config/beacon_keys.dart        (appsFlyerDevKey, firebaseProjectNumber)
//   lib/relay/config/legal_links.dart        (privacyUrl, supportUrl)
//   lib/relay/config/agent_marks.dart        (osVersionToken, safariVersionToken)
//
// The VERIFY block MUST round-trip byte-for-byte. Never hand-edit the arrays;
// re-run this tool after any change to _stormSalt or the cipher algorithm.
//
// ⚠️ Always use `dart run` — never a PowerShell foreach loop, which overflows
// 32-bit ints and produces wrong bytes (symptom: FormatException on the URL).

import 'dart:convert';

import 'package:storm_blitz/core/surge_cipher.dart';

const Map<String, String> _plaintext = <String, String>{
  'configEndpoint': 'https://stormbliitz.com/config.php',
  'gcdBase': 'https://gcdsdk.appsflyer.com',
  'appsFlyerDevKey': '5GfGgdgz6A3SmEyyajJFV7',
  'firebaseProjectNumber': '721144392725',
  'privacyUrl': 'https://stormbliitz.com/privacy-policy.html',
  'supportUrl': 'https://stormbliitz.com/support.html',
  'osVersionToken': '18_6',
  'safariVersionToken': '18.6',
};

void main() {
  final buffer = StringBuffer();
  buffer.writeln('// ==== paste these arrays into the matching config files ====');
  _plaintext.forEach((name, value) {
    final bytes = SurgeCipher.rawTransform(utf8.encode(value));
    buffer.writeln('  static const List<int> $name = <int>[');
    buffer.writeln('    ${bytes.join(', ')},');
    buffer.writeln('  ];');
  });

  buffer.writeln('\n// ==== VERIFY (must equal the plaintext above) ====');
  var ok = true;
  _plaintext.forEach((name, value) {
    final bytes = SurgeCipher.rawTransform(utf8.encode(value));
    final back = SurgeCipher.unscramble(bytes);
    final matches = back == value;
    ok = ok && matches;
    buffer.writeln('$name -> "$back"  ${matches ? 'OK' : 'MISMATCH'}');
  });
  buffer.writeln(ok ? '\nALL ROUND-TRIPS OK' : '\n!!! ROUND-TRIP FAILED !!!');

  // ignore: avoid_print
  print(buffer.toString());
}
