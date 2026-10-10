# FinTrack app

Flutter app for Android and Windows. See the [root README](../README.md) for setup, Supabase configuration and releasing.

```
lib/
  main.dart, app.dart     Startup (Supabase, notifications, preferences) and MaterialApp
  core/                   Env, router, theme, formatters, icons, shared widgets
  data/                   Models, the Supabase repository and Riverpod providers
  features/               One folder per screen area (auth, dashboard, accounts, categories,
                          transactions, budgets, reports, goals, recurring, settings, shell)
  services/               Notifications, update check, Windows URL-scheme registration
test/                     Unit tests (formatters, recurrence, budgets) and form widget tests
```

```sh
flutter run -d windows --dart-define-from-file=env.json
flutter analyze
flutter test
```
