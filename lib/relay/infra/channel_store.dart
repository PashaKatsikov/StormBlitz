import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sky_route.dart';

/// Persists routing mode, the last-known-good partner URL (+ expiry), and push
/// prompt bookkeeping. Content URLs live in the Keychain (secure storage);
/// small flags live in SharedPreferences.
///
/// [FINGERPRINT] key prefix `sb.relay.*` is unique to this project.
class ChannelStore {
  ChannelStore(this._prefs);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kMode = 'sb.relay.mode';
  static const _kSavedUrl = 'sb.relay.saved_url';
  static const _kExpires = 'sb.relay.saved_expires';
  static const _kPushDenied = 'sb.relay.push_os_denied';
  static const _kInviteCooldown = 'sb.relay.invite_cooldown_until';
  static const _kPushAsked = 'sb.relay.push_asked';

  static Future<ChannelStore> open() async =>
      ChannelStore(await SharedPreferences.getInstance());

  // ── Mode ────────────────────────────────────────────────────────────
  SkyRoute readMode() => skyRouteFromName(_prefs.getString(_kMode));

  Future<void> writeMode(SkyRoute mode) =>
      _prefs.setString(_kMode, mode.storageName);

  // ── Saved partner URL ───────────────────────────────────────────────
  Future<void> saveDestination(String url, int? expires) async {
    await _secure.write(key: _kSavedUrl, value: url);
    if (expires != null) {
      await _prefs.setInt(_kExpires, expires);
    } else {
      await _prefs.remove(_kExpires);
    }
  }

  Future<String?> readSavedUrl() => _secure.read(key: _kSavedUrl);

  int? readExpires() => _prefs.getInt(_kExpires);

  bool get savedUrlExpired {
    final exp = readExpires();
    if (exp == null) return false; // no expiry given → always valid
    return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp;
  }

  // ── Push prompt bookkeeping ─────────────────────────────────────────
  bool get pushOsDenied => _prefs.getBool(_kPushDenied) ?? false;
  Future<void> markPushOsDenied() => _prefs.setBool(_kPushDenied, true);

  bool get pushEverAsked => _prefs.getBool(_kPushAsked) ?? false;
  Future<void> markPushAsked() => _prefs.setBool(_kPushAsked, true);

  Future<void> writeInviteCooldown(Duration cooldown) => _prefs.setInt(
        _kInviteCooldown,
        DateTime.now().add(cooldown).millisecondsSinceEpoch,
      );

  bool get inviteCoolingDown {
    final until = _prefs.getInt(_kInviteCooldown);
    if (until == null) return false;
    return DateTime.now().millisecondsSinceEpoch < until;
  }

  /// Show the push-permission promo only when the OS has not permanently
  /// denied it, we are not inside a Skip cooldown.
  bool get needsPushPrompt => !pushOsDenied && !inviteCoolingDown;
}
