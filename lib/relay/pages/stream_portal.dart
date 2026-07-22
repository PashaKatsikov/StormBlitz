import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/relay_log.dart';
import '../relay_services.dart';
import 'bolt_splash.dart';
import 'no_signal_page.dart';

/// The partner content shell. A full-screen WKWebView that feels native:
/// forged UA, zoom/tap/overscroll locks, safe-area padding on all sides,
/// rotation reflow, and the mandatory cold-start-push viewport fix.
class StreamPortal extends StatefulWidget {
  const StreamPortal({
    super.key,
    required this.services,
    required this.url,
    this.coldStartPush = false,
  });

  final RelayServices services;
  final String url;
  final bool coldStartPush;

  @override
  State<StreamPortal> createState() => _StreamPortalState();
}

class _StreamPortalState extends State<StreamPortal>
    with WidgetsBindingObserver {
  late final WebViewController _wv;
  bool _viewportReady = false;
  bool _coldReloadDone = false;
  int _redirectRetries = 0;
  String? _lastMainFrameUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _wv = _buildController();

    if (widget.coldStartPush) {
      _settleColdViewport();
    } else {
      _applyImmersive();
      _viewportReady = true;
      _wv.loadRequest(Uri.parse(widget.url));
    }
  }

  WebViewController _buildController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final c = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(widget.services.userAgent)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onError,
        ),
      );
    return c;
  }

  void _applyImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // Layer 2: settle in the CURRENT orientation (no rotation nudge), then mount.
  Future<void> _settleColdViewport() async {
    _applyImmersive();
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() => _viewportReady = true);
    await _wv.loadRequest(Uri.parse(widget.url));
  }

  // Layer 1: rebuild when viewPadding changes; also poke a reflow on rotation.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    setState(() {});
    _pokeReflow();
  }

  void _pokeReflow() {
    const delays = [40, 160, 320, 560, 850];
    for (final ms in delays) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _wv.runJavaScript(
          "window.dispatchEvent(new Event('orientationchange'));"
          "window.dispatchEvent(new Event('resize'));"
          "if(window.visualViewport){window.visualViewport.dispatchEvent(new Event('resize'));}",
        );
        _injectInsetGuard();
        _injectZoomLock();
      });
    }
  }

  NavigationDecision _onNavigation(NavigationRequest req) {
    final uri = Uri.tryParse(req.url);
    if (uri != null && uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
      // Hand off tel:/mailto:/external-app schemes to the OS.
      launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
      return NavigationDecision.prevent;
    }
    if (req.isMainFrame) _lastMainFrameUrl = req.url;
    return NavigationDecision.navigate;
  }

  void _onPageFinished(String url) {
    _redirectRetries = 0;
    _injectInsetGuard();
    _injectKeyboardScroll();
    _injectAntiZoom();
    _injectZoomLock();
    _injectTapPolish();
    _injectMediaPlay();

    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      setState(() {}); // re-read viewPadding
      _wv.runJavaScript(
        "window.dispatchEvent(new Event('resize'));"
        "if(window.visualViewport){window.visualViewport.dispatchEvent(new Event('resize'));}",
      );
      _injectInsetGuard();
      if (widget.coldStartPush && !_coldReloadDone) {
        _coldReloadDone = true;
        _wv.reload();
      }
    });
  }

  Future<void> _onError(WebResourceError error) async {
    // WKWebView main-frame flag can be null — treat null as main frame.
    final mainFrame = error.isForMainFrame ?? true;
    if (error.errorCode == -999) return; // cancelled by a newer load
    if (error.errorCode == -1007 && _redirectRetries < 3) {
      // Affiliate redirect chain too long — retry the last main-frame URL.
      _redirectRetries++;
      final target = _lastMainFrameUrl ?? widget.url;
      _wv.loadRequest(Uri.parse(target));
      return;
    }
    if (!mainFrame) return;
    relayLog(() => '[SB] web error ${error.errorCode}: ${error.description}');
    // Transient? Probe once; only show No-Signal if the network is truly down.
    final reachable = await widget.services.reach.canReachNet();
    if (!reachable && mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => NoSignalPage(
            retryBuilder: (_) => BoltSplash(services: widget.services),
          ),
        ),
      );
    }
  }

  // ── JS injections (fingerprint-unique bodies + sentinels) ──────────────
  void _injectInsetGuard() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbInsetGuard) return;
  window.__sbInsetGuard = true;
  function sbKbOpen(){ return window.visualViewport && window.visualViewport.height < window.innerHeight * 0.75; }
  function sbApplyInset(){
    if (sbKbOpen()) return;
    var css =
      ':root{--safe-area-inset-top:0px!important;--safe-area-inset-right:0px!important;'+
      '--safe-area-inset-bottom:0px!important;--safe-area-inset-left:0px!important;'+
      '--sat:0px!important;--sar:0px!important;--sab:0px!important;--sal:0px!important;'+
      '--safe-top:0px!important;--safe-bottom:0px!important;--safe-left:0px!important;--safe-right:0px!important;}'+
      '.app-header,.js-safe-top{padding-top:0!important;margin-top:0!important;}'+
      'html,body{overscroll-behavior:none!important;overscroll-behavior-y:none!important;}';
    var tag = document.getElementById('sb-inset-style');
    if (!tag){ tag = document.createElement('style'); tag.id='sb-inset-style'; document.head.appendChild(tag); }
    tag.textContent = css;
  }
  sbApplyInset();
  window.__sbApplyInset = sbApplyInset;
})();
''');
  }

  void _injectZoomLock() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbZoomLock) return;
  window.__sbZoomLock = true;
  function sbLockViewport(){
    var m = document.querySelector('meta[name=viewport]');
    if (!m){ m = document.createElement('meta'); m.name='viewport'; document.head.appendChild(m); }
    m.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no, viewport-fit=contain');
  }
  sbLockViewport();
  ['gesturestart','gesturechange','gestureend'].forEach(function(ev){
    document.addEventListener(ev, function(e){ e.preventDefault(); }, {passive:false});
  });
  var lastTouch = 0;
  document.addEventListener('touchend', function(e){
    var now = Date.now();
    if (now - lastTouch <= 300){ e.preventDefault(); }
    lastTouch = now;
  }, {passive:false});
  window.__sbLockViewport = sbLockViewport;
})();
''');
  }

  void _injectTapPolish() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbTapPolish) return;
  window.__sbTapPolish = true;
  var css = '*{-webkit-tap-highlight-color:transparent!important;}'+
    ':not(input):not(textarea):not([contenteditable]){-webkit-touch-callout:none;}';
  var tag = document.createElement('style'); tag.textContent = css; document.head.appendChild(tag);
})();
''');
  }

  void _injectMediaPlay() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbMediaPlay) return;
  window.__sbMediaPlay = true;
  function sbPrep(v){
    try { v.setAttribute('playsinline',''); v.setAttribute('webkit-playsinline',''); v.playsInline = true; var p=v.play(); if(p&&p.catch){p.catch(function(){});} } catch(e){}
  }
  document.querySelectorAll('video').forEach(sbPrep);
  new MutationObserver(function(muts){
    muts.forEach(function(m){ Array.prototype.forEach.call(m.addedNodes||[], function(n){
      if (n.tagName === 'VIDEO') sbPrep(n);
      else if (n.querySelectorAll) n.querySelectorAll('video').forEach(sbPrep);
    }); });
  }).observe(document.documentElement, {childList:true, subtree:true});
})();
''');
  }

  void _injectKeyboardScroll() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbKbScroll) return;
  window.__sbKbScroll = true;
  document.addEventListener('focusin', function(e){
    var t = e.target;
    if (!t || !(t.matches && t.matches('input,textarea,select,[contenteditable]'))) return;
    setTimeout(function(){ try { t.scrollIntoView({behavior:'auto', block:'nearest'}); } catch(err){} }, 350);
  }, true);
})();
''');
  }

  void _injectAntiZoom() {
    _wv.runJavaScript('''
(function(){
  if (window.__sbAntiZoom) return;
  window.__sbAntiZoom = true;
  var tag = document.createElement('style');
  tag.textContent = 'input,textarea,select{font-size:max(16px,1em)!important;}';
  document.head.appendChild(tag);
})();
''');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.of(context).viewPadding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _wv.canGoBack()) {
          _wv.goBack();
        }
        // Back on the first page does NOT close the WebView.
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _viewportReady
            ? Padding(
                padding: EdgeInsets.only(
                  top: safe.top,
                  bottom: safe.bottom,
                  left: safe.left,
                  right: safe.right,
                ),
                child: WebViewWidget(controller: _wv),
              )
            : const ColoredBox(color: Colors.black),
      ),
    );
  }
}
