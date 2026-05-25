import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class AnchorApp extends StatelessWidget {
  const AnchorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anchor',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class _ShareEntryApp extends StatelessWidget {
  const _ShareEntryApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: AppTheme.shareOverlay,
      home: const ShareScreen(),
    );
  }
}
