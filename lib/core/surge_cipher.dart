import 'dart:convert';

/// Byte-stream obfuscation for the relay layer's sensitive strings (config
/// endpoint, attribution key, project number, legal links, agent fragments).
///
/// The family here is an RC4-style key-scheduling + pseudo-random generator
/// keyed off [_stormSalt]. The transform is symmetric: the same routine both
/// encodes plaintext and decodes the stored byte arrays, so the generator tool
/// and this decoder can never drift apart.
///
/// [FINGERPRINT] `_stormSalt` and this algorithm family are unique to this
/// project — never copy them across the portfolio.
class SurgeCipher {
  const SurgeCipher._();

  static const String _stormSalt = 'q7:Storm!Kx>9';

  static List<int> get _key => utf8.encode(_stormSalt);

  /// Symmetric keystream transform. Feed plaintext bytes to encode, feed the
  /// stored cipher bytes to decode — the output is the inverse either way.
  static List<int> rawTransform(List<int> data) {
    final key = _key;
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xff;
      final tmp = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }
    final out = List<int>.filled(data.length, 0);
    var a = 0;
    var b = 0;
    for (var k = 0; k < data.length; k++) {
      a = (a + 1) & 0xff;
      b = (b + s[a]) & 0xff;
      final tmp = s[a];
      s[a] = s[b];
      s[b] = tmp;
      final ks = s[(s[a] + s[b]) & 0xff];
      out[k] = data[k] ^ ks;
    }
    return out;
  }

  /// Decode a stored byte array back to its UTF-8 string.
  static String unscramble(List<int> bytes) => utf8.decode(rawTransform(bytes));
}
