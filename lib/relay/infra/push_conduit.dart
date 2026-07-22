import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/relay_log.dart';

/// Owns Firebase Messaging: permission, APNs/FCM token retrieval (with the
/// mandatory APNs poll on iOS), foreground presentation, and warm/background
/// push-tap URL extraction. Cold-start taps are handled natively by
/// SceneDelegate → [ColdLinkReader]; this class covers everything else.
class PushConduit {
  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  bool _permissionInFlight = false;
  String? _token;

  String? get token => _token;

  /// Fires whenever a fresh FCM token becomes available (initial fetch or
  /// refresh) — the coordinator re-POSTs the config with the token.
  void Function(String token)? onTokenReady;

  /// Fires when a push is tapped while the app is alive/backgrounded. If no
  /// handler is registered yet (e.g. the WebView is not mounted), the URL is
  /// buffered and delivered as soon as a handler is set — otherwise the tapped
  /// link would be silently dropped.
  void Function(String url)? _onPushTapUrl;
  String? _pendingTapUrl;

  set onPushTapUrl(void Function(String url)? handler) {
    _onPushTapUrl = handler;
    final pending = _pendingTapUrl;
    if (handler != null && pending != null) {
      _pendingTapUrl = null;
      handler(pending);
    }
  }

  void _deliverTapUrl(String url) {
    final handler = _onPushTapUrl;
    if (handler != null) {
      handler(url);
    } else {
      _pendingTapUrl = url; // drained when a handler is registered
    }
  }

  Future<void> bootstrap() async {
    try {
      await _fm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _fm.onTokenRefresh.listen((t) {
        if (t.isEmpty) return;
        _token = t;
        relayLog(() => '[SB] token refresh');
        onTokenReady?.call(t);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        final url = _extractUrl(m.data);
        if (url != null) _deliverTapUrl(url);
      });
      await _tryFetchToken();
    } catch (e) {
      relayLog(() => '[SB] push bootstrap failed: $e');
    }
  }

  bool _isGranted(AuthorizationStatus s) =>
      s == AuthorizationStatus.authorized ||
      s == AuthorizationStatus.provisional;

  Future<void> _tryFetchToken({int apnsTries = 5, int apnsDelayMs = 500}) async {
    try {
      final settings = await _fm.getNotificationSettings();
      if (!_isGranted(settings.authorizationStatus)) return;
      // APNs token is null on iOS until registration completes — poll first.
      for (var i = 0; i < apnsTries; i++) {
        final apns = await _fm.getAPNSToken();
        if (apns != null && apns.isNotEmpty) break;
        await Future<void>.delayed(Duration(milliseconds: apnsDelayMs));
      }
      final t = await _fm.getToken();
      if (t != null && t.isNotEmpty) {
        _token = t;
        onTokenReady?.call(t);
      }
    } catch (e) {
      relayLog(() => '[SB] token fetch failed: $e');
    }
  }

  Future<bool> shouldOfferConsent() async {
    try {
      final s = await _fm.getNotificationSettings();
      return s.authorizationStatus == AuthorizationStatus.notDetermined;
    } catch (_) {
      return true;
    }
  }

  /// Requests the system permission dialog. Guarded against concurrent calls
  /// (`permissions request already running`). Returns as soon as the user
  /// answers the SYSTEM dialog — the APNs/FCM token poll runs in the BACKGROUND
  /// so the push-invite screen can dismiss immediately (never block the UI on
  /// the token; `onTokenReady` re-POSTs the config once it arrives).
  Future<bool> askPermission() async {
    if (_permissionInFlight) return false;
    _permissionInFlight = true;
    try {
      final s = await _fm.requestPermission(alert: true, badge: true, sound: true);
      final granted = _isGranted(s.authorizationStatus);
      if (granted) {
        // Fire-and-forget: poll for the token off the UI path.
        unawaited(_tryFetchToken(apnsTries: 14, apnsDelayMs: 700));
      }
      return granted;
    } catch (e) {
      relayLog(() => '[SB] askPermission failed: $e');
      return false;
    } finally {
      _permissionInFlight = false;
    }
  }

  /// Secondary cold-start path (usually nil on iOS — SceneDelegate wins).
  Future<String?> initialTapUrl() async {
    try {
      final m = await _fm.getInitialMessage();
      if (m != null) return _extractUrl(m.data);
    } catch (_) {}
    return null;
  }

  String? _extractUrl(Map<String, dynamic> data) {
    const keys = ['url', 'link', 'target', 'deeplink', 'deep_link'];
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.isNotEmpty) return v;
    }
    for (final nestKey in ['data', 'payload']) {
      final nested = data[nestKey];
      if (nested is Map) {
        for (final k in keys) {
          final v = nested[k];
          if (v is String && v.isNotEmpty) return v;
        }
      }
    }
    return null;
  }
}
