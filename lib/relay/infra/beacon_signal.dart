import 'dart:async';
import 'dart:convert';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

import '../../core/relay_log.dart';
import '../config/relay_config.dart';
import 'masked_client.dart';

/// AppsFlyer attribution wrapper.
///
/// Collects `onInstallConversionData`, `onAppOpenAttribution` and
/// `onDeepLinking` payloads, resolves the Organic false-positive via the GCD
/// API, and assembles the flat config-request body per the authoritative
/// contract in gray_flow_guide.md.
class BeaconSignal {
  BeaconSignal(this._client);

  final MaskedClient _client;

  final Completer<void> _conversionDone = Completer<void>();
  Map<String, dynamic>? _install;
  Map<String, dynamic>? _openAttr;
  Map<String, dynamic>? _deepLink;
  String? _uid;

  String? get appsFlyerUid => _uid;
  String? get afStatus => _install?['af_status'] as String?;

  Future<void> warmup() async {
    try {
      final options = AppsFlyerOptions(
        afDevKey: RelayConfig.appsFlyerDevKey,
        appId: RelayConfig.iosStoreId,
        showDebug: false,
        timeToWaitForATTUserAuthorization: 15.0,
      );
      final sdk = AppsflyerSdk(options);

      sdk.onInstallConversionData((dynamic res) {
        _install = _payloadOf(res);
        relayLog(() => '[SB] onInstallConversionData: $_install');
        if (!_conversionDone.isCompleted) _conversionDone.complete();
      });
      sdk.onAppOpenAttribution((dynamic res) {
        _openAttr = _payloadOf(res);
        relayLog(() => '[SB] onAppOpenAttribution: $_openAttr');
      });
      sdk.onDeepLinking((DeepLinkResult dp) {
        final ce = dp.deepLink?.clickEvent;
        if (ce != null) _deepLink = Map<String, dynamic>.from(ce);
        relayLog(() => '[SB] onDeepLinking(${dp.status}): $_deepLink');
      });

      await sdk.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      _uid = await sdk.getAppsFlyerUID();
    } catch (e) {
      relayLog(() => '[SB] AppsFlyer warmup failed: $e');
      if (!_conversionDone.isCompleted) _conversionDone.complete();
    }
  }

  Map<String, dynamic>? _payloadOf(dynamic res) {
    if (res is Map && res['payload'] is Map) {
      return Map<String, dynamic>.from(res['payload'] as Map);
    }
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
  }

  /// Wait for the install conversion callback, bounded by [timeout]. A failure
  /// or timeout never hangs the boot — we proceed with whatever we have.
  Future<void> awaitConversion([Duration? timeout]) async {
    try {
      await _conversionDone.future
          .timeout(timeout ?? RelayConfig.conversionWait);
    } catch (_) {
      // proceed with partial / no attribution
    }
  }

  /// Give the deferred deep-link callback a brief window to arrive.
  Future<void> awaitDeepLink(
      [Duration wait = const Duration(seconds: 2)]) async {
    if (_deepLink != null) return;
    await Future<void>.delayed(wait);
  }

  /// Organic false-positive fix (gray_flow_lessons.md item 11): if the install
  /// data reports Organic, wait and re-query via the GCD API using the NUMERIC
  /// store id (`id<iosStoreId>`), not the bundle id.
  Future<void> resolveOrganicIfNeeded() async {
    if (afStatus != 'Organic') return;
    final uid = _uid;
    if (uid == null) return;
    await Future<void>.delayed(RelayConfig.organicRetryDelay);
    try {
      final uri = Uri.parse(
        '${RelayConfig.gcdBase}/install_data/v5.0/'
        '${RelayConfig.platformStoreId}?device_id=$uid',
      );
      final resp = await _client
          .getWithAuth(uri, RelayConfig.appsFlyerDevKey)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          _install = Map<String, dynamic>.from(data);
          relayLog(() => '[SB] GCD retry data: $_install');
        }
      }
    } catch (e) {
      relayLog(() => '[SB] GCD retry failed: $e');
    }
  }

  /// Assemble the flat config-request body. AppsFlyer keys are forwarded
  /// verbatim (never renamed/dropped); device-side fields overwrite last.
  Map<String, dynamic> buildPayload({
    required String locale,
    String? pushToken,
    String? idfa,
  }) {
    final body = <String, dynamic>{};
    final install = _install;
    if (install != null) body.addAll(install);
    _openAttr?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _deepLink?.forEach((k, v) => body.putIfAbsent(k, () => v));

    // Device-side fields (always overwrite).
    if (_uid != null) body['af_id'] = _uid;
    body['bundle_id'] = RelayConfig.bundleId;
    body['os'] = 'iOS';
    body['store_id'] = RelayConfig.platformStoreId;
    body['locale'] = locale;
    // Omit push_token + firebase_project_id ENTIRELY when the token is not
    // ready — never send empty/null (backend mis-routes on a leaked sentinel).
    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
      body['firebase_project_id'] = RelayConfig.firebaseProjectNumber;
    }
    if (idfa != null && idfa.isNotEmpty && idfa != '00000000-0000-0000-0000-000000000000') {
      body['sub_id_10'] = idfa;
    }
    return body;
  }
}
