import 'dart:async';
import 'dart:ui' as ui;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import '../core/relay_log.dart';
import 'infra/cold_link_reader.dart';
import 'models/relay_reply.dart';
import 'models/sky_route.dart';
import 'relay_services.dart';

/// The whole routing brain. `decide()` runs the boot pipeline once; concurrent
/// calls are de-duped, but the cache clears on completion so a later Retry from
/// the No-Signal screen re-runs the full pipeline (gray_flow_lessons.md item 3).
class SkyRouter {
  SkyRouter(this._svc);

  final RelayServices _svc;
  Future<RelayOutcome>? _inflight;
  bool _attRequested = false;

  Future<RelayOutcome> decide() =>
      _inflight ??= _run().whenComplete(() => _inflight = null);

  Future<RelayOutcome> _run() async {
    // 1. HIGHEST PRIORITY (all modes): consume a cold-start push tap FIRST,
    //    before push bootstrap / network / attribution.
    final coldUrl = await ColdLinkReader.consumeTapUrl();
    if (coldUrl != null) {
      await _svc.store.writeMode(SkyRoute.web);
      unawaited(_backgroundAttribution());
      return RelayOutcome.web(coldUrl, coldStartPush: true);
    }

    switch (_svc.store.readMode()) {
      case SkyRoute.fresh:
        return _handleFresh();
      case SkyRoute.web:
        return _handleWeb();
      case SkyRoute.game:
        return _handleGame();
    }
  }

  // ── FRESH (first launch) ────────────────────────────────────────────
  Future<RelayOutcome> _handleFresh() async {
    if (await _svc.reach.isOffline()) {
      return const RelayOutcome.offline(); // stays fresh — do not commit game
    }
    await _svc.push.bootstrap();
    await _svc.signal.warmup();
    _wireTokenRefresh();
    await _svc.signal.awaitConversion();
    await _svc.signal.awaitDeepLink();
    await _svc.signal.resolveOrganicIfNeeded();

    final reply = await _dispatch();
    if (reply.granted && reply.destination != null) {
      await _commitWeb(reply);
      return RelayOutcome.web(reply.destination!);
    }
    if (reply.reachedServer) {
      // Genuine "no url" answer → commit the game path.
      await _svc.store.writeMode(SkyRoute.game);
      return const RelayOutcome.game();
    }
    // Online but transport failed → leave mode fresh (retry next launch),
    // show the game for now without committing.
    return const RelayOutcome.game();
  }

  // ── WEB (returning, was WebView) ────────────────────────────────────
  Future<RelayOutcome> _handleWeb() async {
    if (await _svc.reach.isOffline()) return const RelayOutcome.offline();
    await _svc.push.bootstrap();

    final savedUrl = await _svc.store.readSavedUrl();
    // A still-valid saved URL loads without a network round-trip.
    if (savedUrl != null && !_svc.store.savedUrlExpired) {
      _wireTokenRefresh();
      unawaited(_svc.signal.warmup());
      return RelayOutcome.web(savedUrl);
    }

    await _svc.signal.warmup();
    _wireTokenRefresh();
    await _svc.signal.awaitConversion();
    await _svc.signal.awaitDeepLink();
    await _svc.signal.resolveOrganicIfNeeded();

    final reply = await _dispatch();
    if (reply.granted && reply.destination != null) {
      await _commitWeb(reply);
      return RelayOutcome.web(reply.destination!);
    }
    // Never fall back to the game or a blank screen: last-known-good wins.
    if (savedUrl != null) return RelayOutcome.web(savedUrl);
    return const RelayOutcome.offline();
  }

  // ── GAME (returning, was game) ──────────────────────────────────────
  Future<RelayOutcome> _handleGame() async {
    if (await _svc.reach.isOffline()) return const RelayOutcome.game();
    // Re-conversion attempt: a game user CAN become a web user if the backend
    // starts returning a URL.
    await _svc.push.bootstrap();
    await _svc.signal.warmup();
    _wireTokenRefresh();
    await _svc.signal.awaitConversion();
    await _svc.signal.awaitDeepLink();
    await _svc.signal.resolveOrganicIfNeeded();

    final reply = await _dispatch();
    if (reply.granted && reply.destination != null) {
      await _commitWeb(reply);
      return RelayOutcome.web(reply.destination!);
    }
    return const RelayOutcome.game();
  }

  // ── Shared helpers ──────────────────────────────────────────────────
  Future<RelayReply> _dispatch() async {
    final body = _svc.signal.buildPayload(
      locale: _deviceLocale(),
      pushToken: _svc.push.token,
      idfa: await _resolveIdfa(),
    );
    return _svc.dispatch.send(body);
  }

  Future<void> _commitWeb(RelayReply reply) async {
    await _svc.store.writeMode(SkyRoute.web);
    await _svc.store.saveDestination(reply.destination!, reply.expires);
  }

  /// When the FCM token arrives after the first config POST, immediately
  /// re-POST with the token and persist any returned URL (§5 recovery).
  void _wireTokenRefresh() {
    _svc.push.onTokenReady = (String token) async {
      try {
        final body = _svc.signal.buildPayload(
          locale: _deviceLocale(),
          pushToken: token,
          idfa: await _resolveIdfa(),
        );
        final reply = await _svc.dispatch.send(body);
        if (reply.granted && reply.destination != null) {
          await _commitWeb(reply);
        }
      } catch (e) {
        relayLog(() => '[SB] token re-post failed: $e');
      }
    };
  }

  Future<void> _backgroundAttribution() async {
    try {
      await _svc.push.bootstrap();
      await _svc.signal.warmup();
      _wireTokenRefresh();
      await _svc.signal.awaitConversion();
      await _svc.signal.resolveOrganicIfNeeded();
      final reply = await _dispatch();
      if (reply.granted && reply.destination != null) {
        await _commitWeb(reply);
      }
    } catch (e) {
      relayLog(() => '[SB] background attribution failed: $e');
    }
  }

  Future<String?> _resolveIdfa() async {
    try {
      if (!_attRequested) {
        _attRequested = true;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
      final status =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.authorized) {
        return AppTrackingTransparency.getAdvertisingIdentifier();
      }
    } catch (e) {
      relayLog(() => '[SB] ATT/IDFA failed: $e');
    }
    return null;
  }

  String _deviceLocale() {
    final l = ui.PlatformDispatcher.instance.locale;
    final region = l.countryCode;
    return (region != null && region.isNotEmpty)
        ? '${l.languageCode}_$region'
        : l.languageCode;
  }
}
