import UserNotifications

#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

/// Rich-media push. Lets iOS attach the image from the payload while the app is
/// backgrounded or killed. Without this extension images only render while the
/// Dart isolate is alive.
class NotificationService: UNNotificationServiceExtension {
  var contentHandler: ((UNNotificationContent) -> Void)?
  var bestAttemptContent: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent
    guard let best = bestAttemptContent else {
      contentHandler(request.content)
      return
    }
    #if canImport(FirebaseMessaging)
    Messaging.serviceExtension().populateNotificationContent(best, withContentHandler: contentHandler)
    #else
    contentHandler(best)
    #endif
  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let best = bestAttemptContent {
      handler(best)
    }
  }
}
