import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/share/share_screen.dart';
import 'firebase_options.dart';

void main() async {
  await _init();
  runApp(const ProviderScope(child: AnchorApp()));
}

@pragma('vm:entry-point')
void shareTarget() async {
  await _init();
  runApp(const ProviderScope(child: _ShareEntryApp()));
}

Future<void> _init() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
}

// Workaround for Flutter/Impeller bug on Android: configurationId becomes
// INT_MIN after activity transitions, causing SystemTextScaler to crash.
Widget _fixedScaleBuilder(BuildContext context, Widget? child) =>
    MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.0),
      ),
      child: child!,
    );

class AnchorApp extends StatelessWidget {
  const AnchorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        title: 'Anchor',
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: _fixedScaleBuilder,
        home: const AuthGate(),
      ),
    );
  }
}

class _ShareEntryApp extends StatelessWidget {
  const _ShareEntryApp();

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        theme: AppTheme.shareOverlay,
        builder: _fixedScaleBuilder,
        home: const ShareScreen(),
      ),
    );
  }
}
