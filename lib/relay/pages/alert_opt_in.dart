import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../config/relay_config.dart';
import '../relay_services.dart';
import 'stream_portal.dart';

/// Push opt-in promo shown before the WebView on first entry into web mode.
/// Both Accept and Skip are real, visible buttons; both then forward to the
/// WebView.
class AlertOptIn extends StatefulWidget {
  const AlertOptIn({super.key, required this.services, required this.url});

  final RelayServices services;
  final String url;

  @override
  State<AlertOptIn> createState() => _AlertOptInState();
}

class _AlertOptInState extends State<AlertOptIn> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.services.store.markPushAsked();
    final granted = await widget.services.push.askPermission();
    if (!granted) {
      await widget.services.store.markPushOsDenied();
    }
    _forward();
  }

  Future<void> _skip() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.services.store.markPushAsked();
    await widget.services.store.writeInviteCooldown(RelayConfig.pushCooldown);
    _forward();
  }

  void _forward() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) =>
            StreamPortal(services: widget.services, url: widget.url),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final asset = isPortrait
              ? 'assets/additional_assets/Vertical_Notifications_Screen.webp'
              : 'assets/additional_assets/Horizontal_Notifications_Screen.webp';
          final width = MediaQuery.of(context).size.width;
          final btnWidth =
              (isPortrait ? width * 0.72 : width * 0.42).clamp(240.0, 420.0);
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
              Align(
                alignment: Alignment(0, isPortrait ? 0.82 : 0.72),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _button(
                      width: btnWidth,
                      label: 'ALLOW NOTIFICATIONS',
                      colors: const [AppColors.lightningDeep, AppColors.lightning],
                      onTap: _accept,
                    ),
                    const SizedBox(height: 14),
                    _button(
                      width: btnWidth,
                      label: 'MAYBE LATER',
                      colors: const [Color(0xFF394761), Color(0xFF55618A)],
                      onTap: _skip,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _button({
    required double width,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: colors),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.45),
              blurRadius: 12,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : onTap,
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.title(17, color: Colors.white)
                    .copyWith(height: 1.0, letterSpacing: 1.2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
