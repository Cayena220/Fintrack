/// Build-time configuration, supplied with:
///   flutter run --dart-define-from-file=env.json
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google sign-in is off until the Google Cloud OAuth clients exist and
  /// the provider is enabled in Supabase. Set ENABLE_GOOGLE_SIGN_IN to true
  /// in env.json to show the button.
  static const googleSignInEnabled = bool.fromEnvironment('ENABLE_GOOGLE_SIGN_IN');

  /// Deep link used for OAuth, email confirmation and password reset.
  /// Must be listed under Auth → URL Configuration → Redirect URLs in Supabase.
  static const authRedirectUrl = 'io.fintrack.app://login-callback';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
