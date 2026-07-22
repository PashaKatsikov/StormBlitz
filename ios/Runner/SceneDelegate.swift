import Flutter
import UIKit

/// Captures a cold-start push tap. When the app is launched from a killed state
/// by tapping a notification, iOS delivers the tap here (NOT through Firebase's
/// swizzled path — `getInitialMessage()` returns nil). We extract the URL from
/// the payload and stash it in UserDefaults so Dart can consume it first.
///
/// Key `flutter.sb_launch_link`: the `flutter.` prefix bridges UserDefaults ↔
/// SharedPreferences so `ColdLinkReader` reads it as `sb_launch_link`. Keep the
/// two in sync.
class SceneDelegate: FlutterSceneDelegate {
  static let tapUrlKey = "flutter.sb_launch_link"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    if let response = connectionOptions.notificationResponse {
      captureTapUrl(response.notification.request.content.userInfo)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  private func captureTapUrl(_ userInfo: [AnyHashable: Any]) {
    if let url = SceneDelegate.extractUrl(userInfo) {
      UserDefaults.standard.set(url, forKey: SceneDelegate.tapUrlKey)
    }
  }

  static func extractUrl(_ userInfo: [AnyHashable: Any]) -> String? {
    let keys = ["url", "link", "target", "deeplink", "deep_link"]
    for k in keys {
      if let v = userInfo[k] as? String, !v.isEmpty { return v }
    }
    for nest in ["data", "payload"] {
      if let inner = userInfo[nest] as? [AnyHashable: Any] {
        for k in keys {
          if let v = inner[k] as? String, !v.isEmpty { return v }
        }
      }
    }
    return nil
  }
}
