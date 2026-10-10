# FinTrack

Personal finance and expense tracker for **Android** and **Windows**, built with Flutter and Supabase.

It covers accounts, income/expense/transfer tracking, monthly budgets with alerts, reports with CSV export, savings goals and recurring bills. People download it from a static landing page.

```
app/         Flutter app (Android + Windows)
supabase/    Database migrations, pgTAP tests, local config and seed data
website/     Static download page and privacy policy
installer/   Inno Setup script for the Windows installer
scripts/     publish-release.mjs: uploads a build and records it in app_versions
```

## Prerequisites

| Tool | Needed for |
|---|---|
| Flutter SDK (stable) | Everything in `app/` |
| Android Studio + Android SDK | Android builds and the emulator |
| Visual Studio 2022+ with **Desktop development with C++**, including **C++ CMake tools for Windows** and **C++ ATL** (the notifications plugin needs ATL) | Windows builds |
| Docker Desktop | Running Supabase locally |
| Node 20+ | Supabase CLI (`npx supabase`) and the publish script |
| Inno Setup 6 | Packaging the Windows installer |

Run `flutter doctor` until the Android toolchain and Visual Studio sections show no issues. Also turn on Windows **Developer Mode** (`start ms-settings:developers`), because Flutter needs it for plugin symlinks. Doctor doesn't check for it.

## 1. Supabase

### Local development

```sh
npx supabase start          # needs Docker
npx supabase db reset       # applies migrations/ and seed.sql
npx supabase test db        # pgTAP tests in supabase/tests/
```

The seed creates a demo user, **demo@fintrack.local** with password **password123**, along with three months of transactions, budgets, goals and recurring rules. Emails sent locally show up in Inbucket at http://localhost:54324.

To try the recurring job by hand, move a rule's `next_run_on` to yesterday in Studio (http://localhost:54323), then run `select public.process_recurring_rules();`.

### Hosted project

1. Create a project at supabase.com, then link and push:
   ```sh
   npx supabase login
   npx supabase link --project-ref YOUR-PROJECT-REF
   npx supabase db push
   ```
2. Go to **Database → Extensions** and check that `pg_cron` is enabled. Migration 0005 schedules the daily job.
3. Go to **Authentication → URL Configuration**. Set **Site URL** to `io.fintrack.app://login-callback`, and add the same value under **Redirect URLs**.
4. Go to **Authentication → Providers → Google**. Enable it, paste the **Web** client ID and secret (see below), and turn on **Skip nonce check**, which Android native sign-in needs.
5. Go to **Storage → Settings** and raise the upload size limit if your builds are larger than 50 MB.

### Google OAuth clients (Google Cloud Console)

- **Web application** client: its redirect URI is `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`. Its ID goes in Supabase and in `GOOGLE_WEB_CLIENT_ID`.
- **Android** client: package name `io.fintrack.fintrack`, plus the SHA-1 of **both** your debug keystore and your upload keystore:
  ```sh
  keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android
  keytool -list -v -keystore app/android/upload-keystore.jks -alias upload
  ```
- The OAuth consent screen needs a privacy policy URL. Use the deployed `privacy.html`.

## 2. App

```sh
cd app
copy env.example.json env.json      # then fill in the URL, publishable key and Google web client ID
flutter pub get
flutter run -d windows --dart-define-from-file=env.json
flutter run -d emulator-5554 --dart-define-from-file=env.json
```

For the local stack, use `http://10.0.2.2:54321` as `SUPABASE_URL` on the Android emulator and `http://127.0.0.1:54321` on Windows. Use the publishable key printed by `npx supabase status`.

Checks:

```sh
flutter analyze
flutter test
```

## 3. Releasing

Bump `version:` in `app/pubspec.yaml` first. Increase the build number after the `+` for every release. Installed apps offer an update only when the published build number is higher than their own.

### Android APK

One-time setup: create an upload keystore and keep it backed up. Losing it means users cannot update to builds signed with a new key.

```sh
keytool -genkey -v -keystore app/android/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
copy app\android\key.properties.example app\android\key.properties   # then fill in the passwords
```

```sh
cd app
flutter build apk --release --dart-define-from-file=env.json
```

The APK is written to `app/build/app/outputs/flutter-apk/app-release.apk`. Without `key.properties`, the release build falls back to the debug key. That's fine for local testing, but never publish a debug-signed build.

### Windows installer

```sh
cd app
flutter build windows --release --dart-define-from-file=env.json
cd ..
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DAppVersion=1.0.0 installer\fintrack.iss
```

The installer is written to `installer/Output/FinTrack-Setup-1.0.0.exe`. It installs per user without an admin prompt, adds Start-menu shortcuts and an uninstaller, and registers the `io.fintrack.app://` link scheme that Google sign-in returns to. Until the installer is code-signed, SmartScreen shows a warning; choose **More info → Run anyway**.

### Publish

Copy `.env.example` to `.env` (git-ignored) and add the project's **secret** key. The secret key must never go into the app or the website.

```sh
node scripts/publish-release.mjs android --notes "Budgets can now be copied from last month." --dry-run
node scripts/publish-release.mjs android --notes "Budgets can now be copied from last month."
node scripts/publish-release.mjs windows --notes "Budgets can now be copied from last month."
```

The script uploads the build to the public `releases` bucket and inserts a row into `app_versions`. If a build with the same or a higher number already exists for that platform, it refuses to publish.

## 4. Website

Fill in `website/config.js` with the project URL and the **publishable** key. That key is safe to expose, because RLS only lets it read `app_versions`. Then deploy the `website/` folder to Netlify or Vercel as a static site with no build command. The page shows the latest version for each platform from `app_versions`.

## Verifying a release end to end

1. Sign up with email, confirm, and sign in. Sign in with Google on both platforms.
2. Add accounts and transactions, including a transfer, and check that the balances add up.
3. Set a budget and overspend it. A notification should appear at the alert threshold and again past 100%.
4. Check the report charts and export a CSV.
5. Add a goal contribution, then a withdrawal.
6. Create a recurring rule that starts yesterday. Saving it should record the missed transaction.
7. Install from the landing page on a phone, and on a clean Windows machine (Windows Sandbox). Check that Google sign-in returns to the desktop app.
8. Publish a build with a higher build number and check that the older install shows **Update available**.
