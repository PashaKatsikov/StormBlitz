import 'agent_marks.dart';
import 'beacon_keys.dart';
import 'legal_links.dart';
import 'relay_endpoints.dart';

/// Central identity + tuning for the relay (gray) layer. Everything sensitive
/// is deref'd through the obfuscated config files; nothing here is a plaintext
/// secret.
class RelayConfig {
  const RelayConfig._();

  // ── App identity ──────────────────────────────────────────────────────
  static const String bundleId = 'com.warsstorm.stormblitz';
  static const String appTitle = 'Storm Blitz';

  /// App name token appended to the slot User-Agent (`appname/<token>`), no
  /// spaces.
  static const String appNameToken = 'StormBlitz';

  /// Numeric App Store id. `platformStoreId` sends it as `id<number>`.
  static const String iosStoreId = '6787726150';
  static String get platformStoreId => 'id$iosStoreId';

  // ── Backend / secrets (obfuscated) ────────────────────────────────────
  static String get configEndpoint => RelayEndpoints.configEndpoint;
  static String get gcdBase => RelayEndpoints.gcdBase;
  static String get appsFlyerDevKey => BeaconKeys.appsFlyerDevKey;
  static String get firebaseProjectNumber => BeaconKeys.firebaseProjectNumber;
  static String get privacyUrl => LegalLinks.privacyUrl;
  static String get supportUrl => LegalLinks.supportUrl;
  static String get uaOsVersion => AgentMarks.osVersionToken;
  static String get uaSafariVersion => AgentMarks.safariVersionToken;

  // ── Timings ───────────────────────────────────────────────────────────
  static const Duration configTimeout = Duration(seconds: 15);
  // Must exceed AppsFlyer's timeToWaitForATTUserAuthorization (5s) so the
  // install-conversion callback (af_status) arrives before we POST the config;
  // otherwise a non-organic user is sent to the game (template uses 8s).
  static const Duration conversionWait = Duration(seconds: 8);
  static const Duration organicRetryDelay = Duration(seconds: 6);
  static const Duration pushCooldown = Duration(days: 3);

  /// The relay is enabled only when the load-bearing credentials decode to
  /// non-empty values. It must NOT depend on optional fields (OneLink, etc.) —
  /// see gray_flow_lessons.md item 4.
  static bool get grayCredentialsReady =>
      configEndpoint.isNotEmpty &&
      appsFlyerDevKey.isNotEmpty &&
      firebaseProjectNumber.isNotEmpty;
}
