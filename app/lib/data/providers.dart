import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/formatters.dart';
import '../core/settings.dart';
import 'models.dart';
import 'offline_store.dart';
import 'repository.dart';
import 'sync.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider = Provider<FinanceRepository>((ref) {
  final db = ref.watch(supabaseProvider);
  final repo = FinanceRepository(db, OfflineStore(ref.watch(sharedPreferencesProvider), () => db.auth.currentUser?.id));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Emits on every sign-in / sign-out / token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(supabaseProvider).auth.onAuthStateChange);

/// The signed-in user's id. Data providers watch this so they reload when a
/// different user signs in.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser?.id;
});

final profileProvider = FutureProvider<Profile?>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return null;
  return ref.watch(repositoryProvider).fetchProfile();
});

final currencyProvider = Provider<String>((ref) => ref.watch(profileProvider).value?.currency ?? 'PHP');

final accountsProvider = FutureProvider<List<Account>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchAccounts();
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchCategories();
});

/// Lookup maps so lists can show names/icons without joins.
final accountMapProvider = Provider<Map<String, Account>>(
    (ref) => {for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) a.id: a});
final categoryMapProvider = Provider<Map<String, Category>>(
    (ref) => {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c});

/// Filters for the transactions list. Records give value equality, which
/// family providers need to cache correctly.
typedef TxFilter = ({DateTime month, TxType? type, String? accountId, String? categoryId, String search});

final transactionsProvider = FutureProvider.family<List<Transaction>, TxFilter>((ref, f) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchTransactions(
        from: monthStart(f.month),
        to: addMonths(monthStart(f.month), 1).subtract(const Duration(days: 1)),
        type: f.type,
        accountId: f.accountId,
        categoryId: f.categoryId,
        search: f.search,
      );
});

final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchTransactions(limit: 8);
});

/// Category totals for an inclusive range of months.
typedef MonthRange = ({DateTime from, DateTime to});

final categoryTotalsProvider = FutureProvider.family<List<CategoryTotal>, MonthRange>((ref, range) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchCategoryTotals(fromMonth: range.from, toMonth: range.to);
});

final budgetsProvider = FutureProvider.family<List<Budget>, DateTime>((ref, month) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchBudgets(month);
});

final goalsProvider = FutureProvider<List<SavingsGoal>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchGoals();
});

final goalContributionsProvider = FutureProvider.family<List<GoalContribution>, String>(
    (ref, goalId) => ref.watch(repositoryProvider).fetchContributions(goalId));

final recurringRulesProvider = FutureProvider<List<RecurringRule>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const [];
  return ref.watch(repositoryProvider).fetchRecurringRules();
});

/// Reloads everything derived from transactions. Call after any write.
void refreshFinanceData(WidgetRef ref) => ref.read(syncControllerProvider.notifier).reloadData();
