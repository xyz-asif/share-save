import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';

/// Watches the Firebase auth state — null = signed out, User = signed in.
final authStateProvider = StreamProvider<User?>((ref) {
  return AuthService.instance.authStateChanges;
});

/// Notifier that exposes sign-in / sign-out actions and tracks loading/error.
class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async => AuthService.instance.currentUser;

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => AuthService.instance.signInWithGoogle(),
    );
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    await AuthService.instance.signOut();
    state = const AsyncData(null);
  }
}

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, User?>(AuthNotifier.new);
