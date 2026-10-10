import '../../data/models.dart';

/// 0 = fine, 1 = past the alert threshold, 2 = over budget.
enum BudgetLevel { ok, warning, over }

BudgetLevel budgetLevel({required int spent, required int limit, required double threshold}) {
  if (limit <= 0) return BudgetLevel.ok;
  if (spent > limit) return BudgetLevel.over;
  if (spent >= limit * threshold) return BudgetLevel.warning;
  return BudgetLevel.ok;
}

/// A budget joined with how much was spent in its category that month.
class BudgetStatus {
  const BudgetStatus({required this.budget, required this.category, required this.spent});
  final Budget budget;
  final Category? category;
  final int spent;

  int get remaining => budget.amount - spent;
  double get ratio => budget.amount == 0 ? 0 : spent / budget.amount;
  BudgetLevel get level => budgetLevel(spent: spent, limit: budget.amount, threshold: budget.alertThreshold);
}

List<BudgetStatus> combineBudgets(
  List<Budget> budgets,
  List<CategoryTotal> totals,
  Map<String, Category> categories,
) {
  final spentByCategory = <String, int>{};
  for (final t in totals) {
    if (t.type == TxType.expense) {
      spentByCategory.update(t.categoryId, (v) => v + t.total, ifAbsent: () => t.total);
    }
  }
  final statuses = [
    for (final b in budgets)
      BudgetStatus(budget: b, category: categories[b.categoryId], spent: spentByCategory[b.categoryId] ?? 0),
  ];
  statuses.sort((a, b) => b.ratio.compareTo(a.ratio));
  return statuses;
}

/// Whether moving from [previous] to [current] deserves a notification:
/// only when the level goes up, so each alert fires once per month.
bool shouldNotify(BudgetLevel previous, BudgetLevel current) => current.index > previous.index;
