import 'package:shared_preferences/shared_preferences.dart';

/// Reads the cold-start push URL that `SceneDelegate.swift` wrote to
/// `UserDefaults` when the app was launched from a killed state by a push tap.
///
/// The native side writes UserDefaults key `flutter.sb_launch_link`; the
/// `flutter.` prefix bridges UserDefaults ↔ SharedPreferences, so Dart reads
/// key `sb_launch_link`. The two MUST stay in sync (including the prefix).
///
/// One-shot: reading also clears it, so a later background/foreground push does
/// not replay a stale URL.
class ColdLinkReader {
  const ColdLinkReader._();

  static const String _key = 'sb_launch_link';

  static Future<String?> consumeTapUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // The value was written natively before the Dart isolate booted; refresh
    // the in-memory cache so we actually see it.
    await prefs.reload();
    final url = prefs.getString(_key);
    if (url == null || url.isEmpty) return null;
    await prefs.remove(_key);
    return url;
  }
}
