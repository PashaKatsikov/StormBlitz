import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

/// No-internet screen. A single Retry button rebuilds a fresh boot splash via
/// [retryBuilder], so the whole pipeline re-runs with its OWN context (never
/// captures the parent's context — gray_flow_lessons.md item 3).
class NoSignalPage extends StatefulWidget {
  const NoSignalPage({super.key, required this.retryBuilder});

  final WidgetBuilder retryBuilder;

  @override
  State<NoSignalPage> createState() => _NoSignalPageState();
}

class _NoSignalPageState extends State<NoSignalPage> {
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    // BootSplash may have locked portrait right before routing; re-enable
    // rotation so this screen turns with the device.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _retry() {
    if (_retrying) return;
    setState(() => _retrying = true);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (ctx, _, _) => widget.retryBuilder(ctx),
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
              ? 'assets/additional_assets/Vertical_Nowifi_Screen.webp'
              : 'assets/additional_assets/Horizontal_Nowifi_Screen.webp';
          final width = MediaQuery.of(context).size.width;
          final btnWidth =
              (isPortrait ? width * 0.70 : width * 0.35).clamp(220.0, 380.0);
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
              // Landscape: no SafeArea, centered horizontally so the notch
              // inset does not skew the button off-centre.
              Align(
                alignment: Alignment(0, isPortrait ? 0.80 : 0.74),
                child: _retryButton(btnWidth),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _retryButton(double width) {
    return SizedBox(
      width: width,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [AppColors.lightningDeep, AppColors.lightning],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.lightning.withValues(alpha: 0.5),
              blurRadius: 12,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _retrying ? null : _retry,
            child: Center(
              child: Text(
                'RETRY',
                textAlign: TextAlign.center,
                style: AppTheme.title(20, color: Colors.white)
                    .copyWith(height: 1.0, letterSpacing: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
