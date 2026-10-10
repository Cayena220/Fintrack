import '../core/formatters.dart';

enum TxType {
  income,
  expense,
  transfer;

  static TxType parse(String v) => TxType.values.byName(v);
  String get label => switch (this) { income => 'Income', expense => 'Expense', transfer => 'Transfer' };
}

enum AccountType {
  cash,
  bank,
  ewallet,
  credit;

  static AccountType parse(String v) => AccountType.values.byName(v);
  String get label => switch (this) { cash => 'Cash', bank => 'Bank', ewallet => 'E-wallet', credit => 'Credit card' };
  String get defaultIcon => switch (this) { cash => 'wallet', bank => 'bank', ewallet => 'phone', credit => 'card' };
}

enum Frequency {
  daily,
  weekly,
  monthly,
  yearly;

  static Frequency parse(String v) => Frequency.values.byName(v);
  String unit(int n) => switch (this) {
        daily => n == 1 ? 'day' : 'days',
        weekly => n == 1 ? 'week' : 'weeks',
        monthly => n == 1 ? 'month' : 'months',
        yearly => n == 1 ? 'year' : 'years',
      };
  String describe(int interval) => interval == 1
      ? switch (this) { daily => 'Daily', weekly => 'Weekly', monthly => 'Monthly', yearly => 'Yearly' }
      : 'Every $interval ${unit(interval)}';
}

class Profile {
  const Profile({required this.id, required this.displayName, required this.currency});
  final String id;
  final String? displayName;
  final String currency;

  factory Profile.fromJson(Map<String, dynamic> j) =>
      Profile(id: j['id'] as String, displayName: j['display_name'] as String?, currency: j['currency'] as String);
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.initialBalance,
    required this.balance,
    required this.color,
    required this.icon,
    required this.isArchived,
  });

  final String id;
  final String name;
  final AccountType type;
  final int initialBalance;
  /// Current balance in cents (from the account_balances view).
  final int balance;
  final int color;
  final String icon;
  final bool isArchived;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        name: j['name'] as String,
        type: AccountType.parse(j['type'] as String),
        initialBalance: parseCents(j['initial_balance']),
        balance: parseCents(j['balance'] ?? j['initial_balance']),
        color: (j['color'] as num).toInt(),
        icon: j['icon'] as String,
        isArchived: j['is_archived'] as bool? ?? false,
      );

  Map<String, dynamic> toWriteJson() => {
        'name': name,
        'type': type.name,
        'initial_balance': centsToDecimal(initialBalance),
        'color': color,
        'icon': icon,
        'is_archived': isArchived,
      };
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    required this.isArchived,
  });

  final String id;
  final String name;
  /// income or expense (never transfer).
  final TxType kind;
  final String icon;
  final int color;
  final bool isArchived;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: TxType.parse(j['kind'] as String),
        icon: j['icon'] as String,
        color: (j['color'] as num).toInt(),
        isArchived: j['is_archived'] as bool? ?? false,
      );

  Map<String, dynamic> toWriteJson() =>
      {'name': name, 'kind': kind.name, 'icon': icon, 'color': color, 'is_archived': isArchived};
}

class Transaction {
  const Transaction({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.occurredOn,
    required this.note,
    required this.toAccountId,
    required this.recurringRuleId,
  });

  final String? id;
  final String accountId;
  final String? categoryId;
  final TxType type;
  final int amount;
  final DateTime occurredOn;
  final String? note;
  final String? toAccountId;
  final String? recurringRuleId;

  /// Effect on net worth: + for income, - for expense, 0 for transfers.
  int get signedAmount => switch (type) { TxType.income => amount, TxType.expense => -amount, TxType.transfer => 0 };

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'] as String,
        accountId: j['account_id'] as String,
        categoryId: j['category_id'] as String?,
        type: TxType.parse(j['type'] as String),
        amount: parseCents(j['amount']),
        occurredOn: parseDbDate(j['occurred_on'] as String),
        note: j['note'] as String?,
        toAccountId: j['to_account_id'] as String?,
        recurringRuleId: j['recurring_rule_id'] as String?,
      );

  Map<String, dynamic> toWriteJson() => {
        'account_id': accountId,
        'category_id': type == TxType.transfer ? null : categoryId,
        'type': type.name,
        'amount': centsToDecimal(amount),
        'occurred_on': toDbDate(occurredOn),
        'note': (note == null || note!.trim().isEmpty) ? null : note!.trim(),
        'to_account_id': type == TxType.transfer ? toAccountId : null,
      };
}

/// One row of the monthly_category_totals view.
class CategoryTotal {
  const CategoryTotal({
    required this.month,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.categoryIcon,
    required this.type,
    required this.total,
    required this.count,
  });

  final DateTime month;
  final String categoryId;
  final String categoryName;
  final int categoryColor;
  final String categoryIcon;
  final TxType type;
  final int total;
  final int count;

  factory CategoryTotal.fromJson(Map<String, dynamic> j) => CategoryTotal(
        month: parseDbDate(j['month'] as String),
        categoryId: j['category_id'] as String,
        categoryName: j['category_name'] as String,
        categoryColor: (j['category_color'] as num).toInt(),
        categoryIcon: j['category_icon'] as String,
        type: TxType.parse(j['type'] as String),
        total: parseCents(j['total']),
        count: (j['tx_count'] as num).toInt(),
      );
}

class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.month,
    required this.amount,
    required this.alertThreshold,
  });

  final String? id;
  final String categoryId;
  final DateTime month;
  final int amount;
  final double alertThreshold;

  factory Budget.fromJson(Map<String, dynamic> j) => Budget(
        id: j['id'] as String,
        categoryId: j['category_id'] as String,
        month: parseDbDate(j['month'] as String),
        amount: parseCents(j['amount']),
        alertThreshold: (j['alert_threshold'] as num).toDouble(),
      );

  Map<String, dynamic> toWriteJson() => {
        'category_id': categoryId,
        'month': toDbDate(monthStart(month)),
        'amount': centsToDecimal(amount),
        'alert_threshold': alertThreshold,
      };
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.targetDate,
    required this.icon,
    required this.color,
    required this.isCompleted,
    required this.savedAmount,
  });

  final String? id;
  final String name;
  final int targetAmount;
  final DateTime? targetDate;
  final String icon;
  final int color;
  final bool isCompleted;
  final int savedAmount;

  double get progress => targetAmount == 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1).toDouble();
  int get remaining => (targetAmount - savedAmount).clamp(0, targetAmount);

  factory SavingsGoal.fromJson(Map<String, dynamic> j) => SavingsGoal(
        id: j['id'] as String,
        name: j['name'] as String,
        targetAmount: parseCents(j['target_amount']),
        targetDate: j['target_date'] == null ? null : parseDbDate(j['target_date'] as String),
        icon: j['icon'] as String,
        color: (j['color'] as num).toInt(),
        isCompleted: j['is_completed'] as bool? ?? false,
        savedAmount: parseCents(j['saved_amount']),
      );

  Map<String, dynamic> toWriteJson() => {
        'name': name,
        'target_amount': centsToDecimal(targetAmount),
        'target_date': targetDate == null ? null : toDbDate(targetDate!),
        'icon': icon,
        'color': color,
        'is_completed': isCompleted,
      };
}

class GoalContribution {
  const GoalContribution({required this.id, required this.amount, required this.contributedOn, required this.note});
  final String id;
  final int amount;
  final DateTime contributedOn;
  final String? note;

  factory GoalContribution.fromJson(Map<String, dynamic> j) => GoalContribution(
        id: j['id'] as String,
        amount: parseCents(j['amount']),
        contributedOn: parseDbDate(j['contributed_on'] as String),
        note: j['note'] as String?,
      );
}

class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.note,
    required this.frequency,
    required this.interval,
    required this.startDate,
    required this.nextRunOn,
    required this.endDate,
    required this.isActive,
  });

  final String? id;
  final String accountId;
  final String categoryId;
  final TxType type;
  final int amount;
  final String? note;
  final Frequency frequency;
  final int interval;
  final DateTime startDate;
  final DateTime nextRunOn;
  final DateTime? endDate;
  final bool isActive;

  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
        id: j['id'] as String,
        accountId: j['account_id'] as String,
        categoryId: j['category_id'] as String,
        type: TxType.parse(j['type'] as String),
        amount: parseCents(j['amount']),
        note: j['note'] as String?,
        frequency: Frequency.parse(j['frequency'] as String),
        interval: (j['interval'] as num).toInt(),
        startDate: parseDbDate(j['start_date'] as String),
        nextRunOn: parseDbDate(j['next_run_on'] as String),
        endDate: j['end_date'] == null ? null : parseDbDate(j['end_date'] as String),
        isActive: j['is_active'] as bool,
      );

  Map<String, dynamic> toWriteJson() => {
        'account_id': accountId,
        'category_id': categoryId,
        'type': type.name,
        'amount': centsToDecimal(amount),
        'note': (note == null || note!.trim().isEmpty) ? null : note!.trim(),
        'frequency': frequency.name,
        'interval': interval,
        'start_date': toDbDate(startDate),
        'next_run_on': toDbDate(nextRunOn),
        'end_date': endDate == null ? null : toDbDate(endDate!),
        'is_active': isActive,
      };
}

class AppVersion {
  const AppVersion({
    required this.platform,
    required this.version,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String platform;
  final String version;
  final int buildNumber;
  final String downloadUrl;
  final String? releaseNotes;

  factory AppVersion.fromJson(Map<String, dynamic> j) => AppVersion(
        platform: j['platform'] as String,
        version: j['version'] as String,
        buildNumber: (j['build_number'] as num).toInt(),
        downloadUrl: j['download_url'] as String,
        releaseNotes: j['release_notes'] as String?,
      );
}
