import 'dart:math' as math;

import '../../data/models.dart';

/// Dart mirror of `public.next_recurring_date` in the database, used for
/// previews and for re-scheduling edited rules. Keep the two in sync.
DateTime nextRecurringDate(DateTime d, Frequency frequency, int step, DateTime anchor) {
  switch (frequency) {
    case Frequency.daily:
      return DateTime(d.year, d.month, d.day + step);
    case Frequency.weekly:
      return DateTime(d.year, d.month, d.day + 7 * step);
    case Frequency.monthly:
    case Frequency.yearly:
      final monthsPerStep = frequency == Frequency.monthly ? step : 12 * step;
      final elapsed = (d.year - anchor.year) * 12 + (d.month - anchor.month);
      return addMonthsClamped(anchor, (elapsed ~/ monthsPerStep + 1) * monthsPerStep);
  }
}

/// Adds months, clamping the day to the target month's length
/// (Jan 31 + 1 month = Feb 28/29), like Postgres interval arithmetic.
DateTime addMonthsClamped(DateTime date, int months) {
  final firstOfTarget = DateTime(date.year, date.month + months);
  final daysInTarget = DateTime(firstOfTarget.year, firstOfTarget.month + 1, 0).day;
  return DateTime(firstOfTarget.year, firstOfTarget.month, math.min(date.day, daysInTarget));
}

/// First occurrence of the schedule on or after [target].
DateTime firstOccurrenceOnOrAfter(DateTime target, Frequency frequency, int step, DateTime anchor) {
  var d = DateTime(anchor.year, anchor.month, anchor.day);
  // Bounded so a bad input can never hang the UI.
  for (var i = 0; i < 100000 && d.isBefore(target); i++) {
    d = nextRecurringDate(d, frequency, step, anchor);
  }
  return d;
}

/// The next [count] occurrences starting at [from], for previews.
List<DateTime> upcomingOccurrences(DateTime from, Frequency frequency, int step, DateTime anchor,
    {int count = 3, DateTime? endDate}) {
  final result = <DateTime>[];
  var d = from;
  while (result.length < count && (endDate == null || !d.isAfter(endDate))) {
    result.add(d);
    d = nextRecurringDate(d, frequency, step, anchor);
  }
  return result;
}
