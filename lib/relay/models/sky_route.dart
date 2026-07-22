/// Persisted routing mode for the install.
///
/// - [fresh] — first launch, undecided. A network failure here NEVER commits
///   to [game]; the install stays [fresh] so a later online launch can still
///   reach the web experience.
/// - [web]  — this install was routed to the partner WebView.
/// - [game] — this install was routed to the native game (organic / no url).
enum SkyRoute { fresh, web, game }

SkyRoute skyRouteFromName(String? name) {
  switch (name) {
    case 'web':
      return SkyRoute.web;
    case 'game':
      return SkyRoute.game;
    default:
      return SkyRoute.fresh;
  }
}

extension SkyRouteName on SkyRoute {
  String get storageName => name;
}

/// What the router decided the boot should show.
enum RelayStop { web, game, offline }

/// Immutable result of [SkyRouter.decide].
class RelayOutcome {
  const RelayOutcome.web(String this.url, {this.coldStartPush = false})
      : stop = RelayStop.web;
  const RelayOutcome.game()
      : stop = RelayStop.game,
        url = null,
        coldStartPush = false;
  const RelayOutcome.offline()
      : stop = RelayStop.offline,
        url = null,
        coldStartPush = false;

  final RelayStop stop;
  final String? url;
  final bool coldStartPush;
}
