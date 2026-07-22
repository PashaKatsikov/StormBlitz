import 'dart:math';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/relay_log.dart';
import 'models/player_profile.dart';
import 'relay/config/relay_config.dart';
import 'relay/pages/bolt_splash.dart';
import 'relay/relay_services.dart';
import 'screens/loading_screen.dart';
import 'services/profile_repository.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Rich media is attached by the Notification Service Extension; nothing to do
  // here, but a registered handler is required for data delivery.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Firebase and App Check init are independent: an App Check failure (e.g. a
  // debug-token warning) must never disable attribution or the gate.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
  } catch (e) {
    relayLog(() => '[SB] Firebase init failed: $e');
  }
  try {
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    );
  } catch (e) {
    relayLog(() => '[SB] App Check activate failed: $e');
  }

  // Build the relay layer once (only if credentials decode).
  RelayServices? relay;
  if (RelayConfig.grayCredentialsReady) {
    try {
      relay = await RelayServices.boot();
    } catch (e) {
      relayLog(() => '[SB] relay boot failed: $e');
    }
  }

  // Persistent meta-progression for the white game.
  final repository = ProfileRepository();
  final profile = await repository.load();
  profile.refreshDailyQuests(Random());
  profile.onMutated = () => repository.save(profile);

  runApp(
    ChangeNotifierProvider<PlayerProfile>.value(
      value: profile,
      child: StormBlitzApp(relay: relay),
    ),
  );
}

class StormBlitzApp extends StatelessWidget {
  const StormBlitzApp({super.key, this.relay});

  final RelayServices? relay;

  @override
  Widget build(BuildContext context) {
    final services = relay;
    return MaterialApp(
      title: 'Storm Blitz',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      // Gray flow entry when credentials are ready; otherwise the plain game.
      home: services != null
          ? BoltSplash(services: services)
          : const LoadingScreen(),
    );
  }
}
