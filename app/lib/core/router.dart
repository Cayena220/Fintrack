import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/accounts/account_form_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/auth/auth_screens.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/recurring/recurring_form_screen.dart';
import '../features/recurring/recurring_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/settings/more_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/transactions/transaction_form_screen.dart';
import '../features/transactions/transactions_screen.dart';

/// Re-runs router redirects on auth changes and remembers when the user
/// arrived through a password-reset link.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Stream<AuthState> stream) {
    _sub = stream.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) passwordRecovery = true;
      if (state.event == AuthChangeEvent.signedOut) passwordRecovery = false;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;
  bool passwordRecovery = false;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(supabaseProvider).auth;
  final authListenable = _AuthListenable(auth.onAuthStateChange);
  ref.onDispose(authListenable.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/dashboard',
    refreshListenable: authListenable,
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final location = state.matchedLocation;
      final onAuthPage = location.startsWith('/auth');

      if (signedIn && authListenable.passwordRecovery && location != '/auth/update-password') {
        return '/auth/update-password';
      }
      if (!signedIn) return onAuthPage ? null : '/auth/sign-in';
      if (onAuthPage && location != '/auth/update-password') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/auth/sign-up', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/auth/forgot-password', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/auth/update-password',
        builder: (_, _) => UpdatePasswordScreen(onDone: () => authListenable.passwordRecovery = false),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen())]),
          StatefulShellBranch(
              routes: [GoRoute(path: '/transactions', builder: (_, _) => const TransactionsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/budgets', builder: (_, _) => const BudgetsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())]),
        ],
      ),
      // Full-screen pages pushed above the shell.
      GoRoute(
        path: '/transaction',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => TransactionFormScreen(
          existing: state.extra as Transaction?,
          initialType: TxType.values.asNameMap()[state.uri.queryParameters['type']],
        ),
      ),
      GoRoute(path: '/accounts', parentNavigatorKey: _rootKey, builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/account',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => AccountFormScreen(existing: state.extra as Account?),
      ),
      GoRoute(path: '/categories', parentNavigatorKey: _rootKey, builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/goals', parentNavigatorKey: _rootKey, builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/recurring', parentNavigatorKey: _rootKey, builder: (_, _) => const RecurringScreen()),
      GoRoute(
        path: '/recurring/edit',
        parentNavigatorKey: _rootKey,
        builder: (_, state) => RecurringFormScreen(existing: state.extra as RecurringRule?),
      ),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (_, _) => const SettingsScreen()),
    ],
  );
});
