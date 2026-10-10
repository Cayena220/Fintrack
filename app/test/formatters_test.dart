import 'package:fintrack/core/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCents', () {
    test('reads numbers and numeric strings from Postgres', () {
      expect(parseCents(12.5), 1250);
      expect(parseCents('1234.56'), 123456);
      expect(parseCents(null), 0);
    });

    test('rounds away floating point drift', () {
      expect(parseCents(0.1 + 0.2), 30);
      expect(parseCents(19.99), 1999);
    });
  });

  group('parseAmountInput', () {
    test('accepts thousands separators', () {
      expect(parseAmountInput('1,234.50'), 123450);
      expect(parseAmountInput(' 7 '), 700);
    });

    test('rejects empty or invalid input', () {
      expect(parseAmountInput(''), isNull);
      expect(parseAmountInput('abc'), isNull);
      expect(parseAmountInput('1.2.3'), isNull);
    });
  });

  group('formatMoney', () {
    test('formats with the currency symbol', () {
      expect(formatMoney(123456, 'USD'), r'$1,234.56');
    });

    test('puts the sign in front of the symbol', () {
      expect(formatMoney(-500, 'USD'), r'-$5.00');
      expect(formatMoney(500, 'USD', signed: true), r'+$5.00');
      expect(formatMoney(0, 'USD', signed: true), r'$0.00');
    });
  });

  group('dates', () {
    test('round-trips Postgres dates', () {
      final d = DateTime(2026, 3, 9);
      expect(toDbDate(d), '2026-03-09');
      expect(parseDbDate('2026-03-09'), d);
      expect(parseDbDate('2026-03-09T00:00:00Z'), d);
    });

    test('addMonths crosses year boundaries', () {
      expect(addMonths(DateTime(2026, 12), 1), DateTime(2027, 1));
      expect(addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
    });

    test('formatRelativeDay names nearby days', () {
      final now = DateTime(2026, 10, 10, 15);
      expect(formatRelativeDay(DateTime(2026, 10, 10), now: now), 'Today');
      expect(formatRelativeDay(DateTime(2026, 10, 9), now: now), 'Yesterday');
      expect(formatRelativeDay(DateTime(2026, 10, 11), now: now), 'Tomorrow');
    });
  });
}
