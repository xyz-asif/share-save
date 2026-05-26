import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/share/share_screen.dart';

void main() {
  _init();
  runApp(const ProviderScope(child: AnchorApp()));
}

@pragma('vm:entry-point')
void shareTarget() {
  _init();
  runApp(const ProviderScope(child: _ShareEntryApp()));
}

void _init() {
  WidgetsFlutterBinding.ensureInitialized();
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
        home: const HomeScreen(),
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
