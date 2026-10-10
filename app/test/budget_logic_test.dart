import 'package:fintrack/data/models.dart';
import 'package:fintrack/features/budgets/budget_logic.dart';
import 'package:flutter_test/flutter_test.dart';

CategoryTotal total(String categoryId, int cents, {TxType type = TxType.expense}) => CategoryTotal(
      month: DateTime(2026, 10),
      categoryId: categoryId,
      categoryName: categoryId,
      categoryColor: 0,
      categoryIcon: 'category',
      type: type,
      total: cents,
      count: 1,
    );

Budget budget(String categoryId, int cents) => Budget(
      id: 'b-$categoryId',
      categoryId: categoryId,
      month: DateTime(2026, 10),
      amount: cents,
      alertThreshold: 0.8,
    );

void main() {
  group('budgetLevel', () {
    test('is ok below the threshold', () {
      expect(budgetLevel(spent: 7999, limit: 10000, threshold: 0.8), BudgetLevel.ok);
    });

    test('warns at the threshold', () {
      expect(budgetLevel(spent: 8000, limit: 10000, threshold: 0.8), BudgetLevel.warning);
      expect(budgetLevel(spent: 10000, limit: 10000, threshold: 0.8), BudgetLevel.warning);
    });

    test('is over only past the limit', () {
      expect(budgetLevel(spent: 10001, limit: 10000, threshold: 0.8), BudgetLevel.over);
    });

    test('ignores budgets without a limit', () {
      expect(budgetLevel(spent: 500, limit: 0, threshold: 0.8), BudgetLevel.ok);
    });
  });

  test('shouldNotify only when the level goes up', () {
    expect(shouldNotify(BudgetLevel.ok, BudgetLevel.warning), isTrue);
    expect(shouldNotify(BudgetLevel.warning, BudgetLevel.over), isTrue);
    expect(shouldNotify(BudgetLevel.ok, BudgetLevel.over), isTrue);
    expect(shouldNotify(BudgetLevel.warning, BudgetLevel.warning), isFalse);
    expect(shouldNotify(BudgetLevel.over, BudgetLevel.warning), isFalse);
  });

  test('combineBudgets counts only expenses and sorts by usage', () {
    final statuses = combineBudgets(
      [budget('food', 10000), budget('fun', 5000), budget('bills', 20000)],
      [
        total('food', 3000),
        total('fun', 4500),
        total('fun', 1000),
        total('food', 99999, type: TxType.income),
      ],
      const {},
    );

    expect(statuses.map((s) => s.budget.categoryId), ['fun', 'food', 'bills']);
    expect(statuses[0].spent, 5500);
    expect(statuses[0].level, BudgetLevel.over);
    expect(statuses[0].remaining, -500);
    expect(statuses[1].spent, 3000);
    expect(statuses[2].spent, 0);
  });
}
