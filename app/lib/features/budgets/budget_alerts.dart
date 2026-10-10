import 'package:shared_preferences/shared_preferences.dart';

import '../../core/formatters.dart';
import '../../data/repository.dart';
import '../../services/notification_service.dart';
import 'budget_logic.dart';

/// Compares this month's spending with each budget and notifies once when a
/// budget crosses its alert threshold and once more when it goes over.
Future<void> checkBudgetAlerts(FinanceRepository repo, String currency) async {
  final month = monthStart(DateTime.now());
  final budgets = await repo.fetchBudgets(month);
  if (budgets.isEmpty) return;

  final totals = await repo.fetchCategoryTotals(fromMonth: month, toMonth: month);
  final categories = {for (final c in await repo.fetchCategories()) c.id: c};
  final prefs = await SharedPreferences.getInstance();

  for (final status in combineBudgets(budgets, totals, categories)) {
    final key = 'budget_alert_${status.budget.id}';
    final previous = BudgetLevel.values[prefs.getInt(key) ?? 0];
    final current = status.level;
    if (shouldNotify(previous, current)) {
      final name = status.category?.name ?? 'A category';
      final spent = formatMoney(status.spent, currency);
      final limit = formatMoney(status.budget.amount, currency);
      await NotificationService.instance.show(
        id: status.budget.id.hashCode & 0x7fffffff,
        title: current == BudgetLevel.over ? '$name is over budget' : '$name is close to its budget',
        body: '$spent of $limit spent in ${formatMonth(month)}.',
      );
    }
    // Store the current level even when it drops (e.g. a deleted expense),
    // so the alert can fire again if spending rises past it later.
    await prefs.setInt(key, current.index);
  }
}
