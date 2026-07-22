import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../screens/home_shell_screen.dart';
import '../../theme/app_theme.dart';
import '../models/sky_route.dart';
import '../relay_services.dart';
import '../sky_router.dart';
import 'alert_opt_in.dart';
import 'no_signal_page.dart';
import 'stream_portal.dart';

/// Splash + boot gate. Shows the loading artwork while [SkyRouter] runs the
/// pipeline, then routes to the WebView, the push promo, the game, or the
/// No-Signal screen. This IS the loading UX — the game path navigates straight
/// to the menu (no second loading screen).
class BoltSplash extends StatefulWidget {
  const BoltSplash({super.key, required this.services});

  final RelayServices services;

  @override
  State<BoltSplash> createState() => _BoltSplashState();
}

class _BoltSplashState extends State<BoltSplash> {
  late final SkyRouter _router = SkyRouter(widget.services);
  Timer? _ticker;
  double _progress = 0;
  bool _navigated = false;

  static const double _holdValue = 0.9;

  @override
  void initState() {
    super.initState();
    // The splash may rotate freely; destinations set their own preference.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _creepProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  void _creepProgress() {
    const tick = Duration(milliseconds: 60);
    _ticker = Timer.periodic(tick, (t) {
      if (!mounted) return;
      setState(() {
        _progress += 0.012;
        if (_progress >= _holdValue) {
          _progress = _holdValue;
          t.cancel();
        }
      });
    });
  }

  Future<void> _boot() async {
    final outcome = await _router.decide();
    if (!mounted) return;
    _ticker?.cancel();
    setState(() => _progress = 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _go(outcome);
  }

  Future<void> _go(RelayOutcome outcome) async {
    if (_navigated) return;
    _navigated = true;
    switch (outcome.stop) {
      case RelayStop.offline:
        Navigator.of(context).pushReplacement(
          _fade(NoSignalPage(
            retryBuilder: (_) => BoltSplash(services: widget.services),
          )),
        );
      case RelayStop.game:
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(_fade(const HomeShellScreen()));
      case RelayStop.web:
        final url = outcome.url!;
        final needPrompt = !outcome.coldStartPush &&
            widget.services.store.needsPushPrompt &&
            await widget.services.push.shouldOfferConsent();
        if (!mounted) return;
        if (needPrompt) {
          Navigator.of(context).pushReplacement(_fade(
            AlertOptIn(services: widget.services, url: url),
          ));
        } else {
          Navigator.of(context).pushReplacement(_fade(
            StreamPortal(
              services: widget.services,
              url: url,
              coldStartPush: outcome.coldStartPush,
            ),
          ));
        }
    }
  }

  Route<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final asset = isPortrait
              ? 'assets/Vertical_LoadingScreen.webp'
              : 'assets/Horizontal_LoadingScreen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                asset,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, _, _) =>
                    Container(color: AppColors.background),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.65),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment(0, isPortrait ? 0.66 : 0.82),
                child: _bar(context, isPortrait),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(BuildContext context, bool isPortrait) {
    final width = MediaQuery.of(context).size.width;
    final barWidth = (isPortrait ? width * 0.70 : width * 0.35).clamp(0.0, 340.0);
    const height = 16.0;
    return Container(
      width: barWidth,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(height),
        border:
            Border.all(color: AppColors.gold.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: LayoutBuilder(
          builder: (context, constraints) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            width: constraints.maxWidth * _progress.clamp(0.0, 1.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: const LinearGradient(
                colors: [
                  AppColors.lightningDeep,
                  AppColors.lightning,
                  AppColors.goldLight,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lightning.withValues(alpha: 0.8),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
