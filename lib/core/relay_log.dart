import 'package:flutter/foundation.dart';

/// Assert-wrapped logger. The closure AND its string literals are stripped from
/// release builds, so no `[SB]` tags or endpoint fragments leak into the
/// shipped binary (grep-able strings cluster the portfolio).
///
/// Usage: `relayLog(() => '[SB] some $value');`
void relayLog(String Function() build) {
  assert(() {
    debugPrint(build());
    return true;
  }());
}
