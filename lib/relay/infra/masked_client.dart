import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../config/relay_config.dart';

// GAME THEME CATEGORY: slot  (appid/appname suffix REQUIRED — see
// .cursor/rules/gray_user_agent.mdc). A crash game would OMIT this suffix.

/// Builds and caches a forged Mobile-Safari User-Agent used identically by the
/// HTTP client (config endpoint) and the WebView. It must never contain
/// Dart/Flutter/CFNetwork/Darwin/WebView tokens — the default iOS URLSession
/// and Flutter UAs leak those, so we always override.
class UserAgentForge {
  UserAgentForge._();

  static String? _cached;

  static Future<String> resolve() async {
    final existing = _cached;
    if (existing != null) return existing;
    final ua = await _forge();
    _cached = ua;
    return ua;
  }

  static Future<String> _forge() async {
    var osToken = RelayConfig.uaOsVersion; // fallback (e.g. 18_6)
    var safariToken = RelayConfig.uaSafariVersion; // fallback (e.g. 18.6)
    try {
      final info = await DeviceInfoPlugin().iosInfo;
      final sys = info.systemVersion.trim();
      if (sys.isNotEmpty && RegExp(r'^\d+(\.\d+)*$').hasMatch(sys)) {
        safariToken = sys;
        osToken = sys.replaceAll('.', '_');
      }
    } catch (_) {
      // Keep the obfuscated fallback tokens.
    }
    final base =
        'Mozilla/5.0 (iPhone; CPU iPhone OS $osToken like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$safariToken '
        'Mobile/15E148 Safari/604.1';
    // Slot identity suffix — MUST be the very last segment.
    return '$base appid/${RelayConfig.bundleId} appname/${RelayConfig.appNameToken}';
  }
}

/// Thin HTTP wrapper that stamps every request with the forged device UA.
class MaskedClient {
  MaskedClient._(this.userAgent, this._client);

  final String userAgent;
  final http.Client _client;

  static Future<MaskedClient> create() async {
    final ua = await UserAgentForge.resolve();
    return MaskedClient._(ua, http.Client());
  }

  Map<String, String> _headers([Map<String, String>? extra]) => {
        HttpHeaders.userAgentHeader: userAgent,
        ...?extra,
      };

  Future<http.Response> postJson(
    Uri url, {
    required String body,
    Duration? timeout,
  }) {
    final future = _client.post(
      url,
      headers: _headers({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }),
      body: body,
    );
    return timeout == null ? future : future.timeout(timeout);
  }

  Future<http.Response> getWithAuth(Uri url, String bearer) {
    return _client.get(url, headers: _headers({'Authorization': 'Bearer $bearer'}));
  }

  void dispose() => _client.close();
}
