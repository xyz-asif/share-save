import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../home/home_screen.dart';
import 'auth_provider.dart';
import 'login_screen.dart';

/// Sits at the root of the widget tree and switches between
/// [LoginScreen] and [HomeScreen] based on Firebase auth state.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      // While waiting for Firebase to emit the first auth event
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFFAF0EE),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE05C4B),
            strokeWidth: 2.5,
          ),
        ),
      ),
      // User is signed in → show the app
      data: (user) => user != null ? const HomeScreen() : const LoginScreen(),
      // Something went wrong with the auth stream
      error: (e, _) => Scaffold(
        body: Center(child: Text('Auth error: $e')),
      ),
    );
  }
}
