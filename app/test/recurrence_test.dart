import 'package:fintrack/data/models.dart';
import 'package:fintrack/features/goals/goals_screen.dart';
import 'package:fintrack/features/recurring/recurrence.dart';
import 'package:fintrack/features/recurring/recurring_form_screen.dart';
import 'package:fintrack/features/recurring/recurring_screen.dart';
import 'package:flutter_test/flutter_test.dart';

RecurringRule rule({
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  required DateTime start,
  required DateTime next,
  DateTime? end,
  bool active = true,
}) =>
    RecurringRule(
      id: 'r1',
      accountId: 'a1',
      categoryId: 'c1',
      type: TxType.expense,
      amount: 10000,
      note: null,
      frequency: frequency,
      interval: interval,
      startDate: start,
      nextRunOn: next,
      endDate: end,
      isActive: active,
    );

void main() {
  group('nextRecurringDate', () {
    test('daily and weekly add days', () {
      final d = DateTime(2026, 2, 27);
      expect(nextRecurringDate(d, Frequency.daily, 3, d), DateTime(2026, 3, 2));
      expect(nextRecurringDate(d, Frequency.weekly, 2, d), DateTime(2026, 3, 13));
    });

    test('monthly keeps the anchor day after a short month', () {
      final anchor = DateTime(2026, 1, 31);
      final feb = nextRecurringDate(anchor, Frequency.monthly, 1, anchor);
      expect(feb, DateTime(2026, 2, 28));
      final mar = nextRecurringDate(feb, Frequency.monthly, 1, anchor);
      expect(mar, DateTime(2026, 3, 31));
      expect(nextRecurringDate(mar, Frequency.monthly, 1, anchor), DateTime(2026, 4, 30));
    });

    test('every 3 months steps from the anchor', () {
      final anchor = DateTime(2026, 1, 15);
      expect(nextRecurringDate(anchor, Frequency.monthly, 3, anchor), DateTime(2026, 4, 15));
    });

    test('yearly handles Feb 29', () {
      final anchor = DateTime(2028, 2, 29);
      expect(nextRecurringDate(anchor, Frequency.yearly, 1, anchor), DateTime(2029, 2, 28));
      expect(nextRecurringDate(DateTime(2031, 2, 28), Frequency.yearly, 1, anchor), DateTime(2032, 2, 29));
    });
  });

  test('addMonthsClamped clamps to month length', () {
    expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonthsClamped(DateTime(2026, 11, 30), 3), DateTime(2027, 2, 28));
  });

  test('firstOccurrenceOnOrAfter finds the first date on or after the target', () {
    final anchor = DateTime(2026, 1, 10);
    expect(firstOccurrenceOnOrAfter(DateTime(2026, 3, 10), Frequency.monthly, 1, anchor), DateTime(2026, 3, 10));
    expect(firstOccurrenceOnOrAfter(DateTime(2026, 3, 11), Frequency.monthly, 1, anchor), DateTime(2026, 4, 10));
  });

  test('upcomingOccurrences stops at the end date', () {
    final start = DateTime(2026, 1, 1);
    final dates = upcomingOccurrences(start, Frequency.weekly, 1, start, count: 5, endDate: DateTime(2026, 1, 15));
    expect(dates, [DateTime(2026, 1, 1), DateTime(2026, 1, 8), DateTime(2026, 1, 15)]);
  });

  group('scheduleNextRun', () {
    final today = DateTime(2026, 10, 10);

    test('a new rule starts at its start date', () {
      final start = DateTime(2026, 9, 1);
      expect(
        scheduleNextRun(existing: null, frequency: Frequency.monthly, interval: 1, startDate: start, now: today),
        start,
      );
    });

    test('an unchanged schedule keeps the next run', () {
      final r = rule(start: DateTime(2026, 1, 5), next: DateTime(2026, 11, 5));
      expect(
        scheduleNextRun(existing: r, frequency: r.frequency, interval: 1, startDate: r.startDate, now: today),
        DateTime(2026, 11, 5),
      );
    });

    test('a changed schedule does not repost today', () {
      // Due today was already posted, so next_run_on moved past today.
      final r = rule(frequency: Frequency.weekly, start: DateTime(2026, 10, 10), next: DateTime(2026, 10, 17));
      final next = scheduleNextRun(
          existing: r, frequency: Frequency.daily, interval: 1, startDate: r.startDate, now: today);
      expect(next, DateTime(2026, 10, 11));
    });
  });

  group('resuming a paused rule', () {
    final today = DateTime(2026, 10, 10);

    test('skips the periods missed while paused', () {
      final r = rule(start: DateTime(2026, 1, 15), next: DateTime(2026, 6, 15), active: false);
      expect(resumeDate(r, now: today), DateTime(2026, 10, 15));
      expect(canResume(r, now: today), isTrue);
    });

    test('cannot resume past the end date', () {
      final r = rule(
          start: DateTime(2026, 1, 15), next: DateTime(2026, 6, 15), end: DateTime(2026, 10, 1), active: false);
      expect(canResume(r, now: today), isFalse);
    });
  });

  group('monthlySavingNeeded', () {
    SavingsGoal goal({required int target, int saved = 0, DateTime? date}) => SavingsGoal(
          id: 'g1',
          name: 'Laptop',
          targetAmount: target,
          targetDate: date,
          icon: 'laptop',
          color: 0,
          isCompleted: false,
          savedAmount: saved,
        );
    final today = DateTime(2026, 10, 10);

    test('spreads the remainder over the months left, including this one', () {
      // Oct, Nov, Dec = 3 months for 30,000.00 left.
      final g = goal(target: 4000000, saved: 1000000, date: DateTime(2026, 12, 31));
      expect(monthlySavingNeeded(g, now: today), 1000000);
    });

    test('is null without a date, once reached, or after the date', () {
      expect(monthlySavingNeeded(goal(target: 100), now: today), isNull);
      expect(monthlySavingNeeded(goal(target: 100, saved: 100, date: DateTime(2027)), now: today), isNull);
      expect(monthlySavingNeeded(goal(target: 100, date: DateTime(2026, 1, 1)), now: today), isNull);
    });
  });
}
