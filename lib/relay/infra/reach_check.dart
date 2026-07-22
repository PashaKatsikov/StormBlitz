import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Connectivity gate for the boot pipeline.
///
/// Two separate paths (see gray_flow_lessons.md item 2):
/// - [isOffline] — a fast, no-network check. If the OS reports no transport we
///   go straight to the No-Signal screen; we do NOT run a DNS probe first
///   (a probe can hang for seconds while offline).
/// - [canReachNet] — an active DNS probe used ONLY for recovering from a
///   transient WebView load error, never for the initial offline decision.
class ReachCheck {
  ReachCheck({this.probeHost = 'apple.com'});

  /// [FINGERPRINT] rotate the probe host per project — not the same as sibling
  /// apps (avoid always `cloudflare.com`).
  final String probeHost;

  Future<bool> isOffline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.every((r) => r == ConnectivityResult.none);
    } catch (_) {
      return false; // if we cannot tell, let the pipeline try the network
    }
  }

  Future<bool> canReachNet() async {
    try {
      final addrs = await InternetAddress.lookup(probeHost)
          .timeout(const Duration(seconds: 4));
      return addrs.isNotEmpty && addrs.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
