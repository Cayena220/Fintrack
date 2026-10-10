import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';

bool _googleInitialized = false;

/// Android: native account picker, then exchange the Google ID token with
/// Supabase. Windows: browser OAuth that returns via the app's URL scheme.
/// Returns false when the user cancelled.
Future<bool> signInWithGoogle(SupabaseClient db) async {
  if (Platform.isAndroid) {
    final google = GoogleSignIn.instance;
    if (!_googleInitialized) {
      await google.initialize(serverClientId: Env.googleWebClientId);
      _googleInitialized = true;
    }
    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthException('Google did not return an ID token.');
    await db.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
    return true;
  }

  // The session arrives later through the deep link; the router reacts to
  // the auth state change.
  return db.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: Env.authRedirectUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
  );
}

/// Signs out of Supabase and, on Android, forgets the Google account so the
/// next Google sign-in shows the account picker again.
Future<void> signOutEverywhere(SupabaseClient db) async {
  if (Platform.isAndroid && _googleInitialized) {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Not fatal: the Supabase session below is what matters.
    }
  }
  await db.auth.signOut();
}
