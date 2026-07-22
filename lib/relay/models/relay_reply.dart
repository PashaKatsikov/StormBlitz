/// Parsed response from the config endpoint.
///
/// Success shape (HTTP 200):
///   { "ok": true, "url": "https://…", "expires": 1689002181 }
/// Anything else (non-200, ok:false, socket/DNS/timeout) is a NEGATIVE answer
/// to "show the WebView?" — [granted] is false.
///
/// [reachedServer] distinguishes a real backend answer (HTTP response received,
/// even if ok:false) from a transport failure. This matters on the FIRST launch
/// (`SkyRoute.fresh`): only a genuine "no url" answer commits the game path; a
/// transport failure must leave the install undecided so a later online launch
/// can still reach the web experience.
class RelayReply {
  const RelayReply({
    required this.granted,
    required this.reachedServer,
    this.destination,
    this.expires,
  });

  const RelayReply.denied()
      : granted = false,
        reachedServer = false,
        destination = null,
        expires = null;

  const RelayReply.rejected()
      : granted = false,
        reachedServer = true,
        destination = null,
        expires = null;

  final bool granted;
  final bool reachedServer;
  final String? destination;

  /// Unix seconds when a saved URL should be refetched. Null = no expiry given.
  final int? expires;

  factory RelayReply.fromJson(Map<String, dynamic> json) {
    final ok = json['ok'] == true;
    final url = json['url'];
    final hasUrl = url is String && url.isNotEmpty;
    final rawExpires = json['expires'];
    final expires = rawExpires is int
        ? rawExpires
        : (rawExpires is String ? int.tryParse(rawExpires) : null);
    return RelayReply(
      granted: ok && hasUrl,
      reachedServer: true,
      destination: hasUrl ? url : null,
      expires: expires,
    );
  }
}
