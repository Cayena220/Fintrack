import 'package:intl/intl.dart';

/// Money is kept as integer cents everywhere in the app to avoid floating
/// point drift; these helpers convert at the edges.
int parseCents(Object? value) {
  if (value == null) return 0;
  if (value is num) return (value * 100).round();
  return ((num.tryParse(value.toString()) ?? 0) * 100).round();
}

double centsToDecimal(int cents) => cents / 100;

/// Parses user input like "1,234.50" into cents. Returns null when invalid.
int? parseAmountInput(String input) {
  final cleaned = input.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  final value = num.tryParse(cleaned);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return (value * 100).round();
}

final _formatCache = <String, NumberFormat>{};

String formatMoney(int cents, String currency, {bool signed = false, bool compact = false}) {
  final key = '$currency|$compact';
  final format = _formatCache.putIfAbsent(key, () {
    final symbol = NumberFormat.simpleCurrency(name: currency).currencySymbol;
    return compact
        ? NumberFormat.compactCurrency(symbol: symbol, decimalDigits: 1)
        : NumberFormat.currency(name: currency, symbol: symbol, decimalDigits: 2);
  });
  final text = format.format(cents.abs() / 100);
  if (cents < 0) return '-$text';
  if (signed && cents > 0) return '+$text';
  return text;
}

String currencySymbol(String currency) => NumberFormat.simpleCurrency(name: currency).currencySymbol;

/// yyyy-MM-dd, the format Postgres `date` columns use.
String toDbDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime parseDbDate(String value) {
  final parts = value.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);
DateTime addMonths(DateTime month, int delta) => DateTime(month.year, month.month + delta);

String formatMonth(DateTime d) => DateFormat.yMMMM().format(d);
String formatShortMonth(DateTime d) => DateFormat.MMM().format(d);
String formatDate(DateTime d) => DateFormat.yMMMd().format(d);

String formatRelativeDay(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = today.difference(dateOnly(d)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff == -1) return 'Tomorrow';
  return DateFormat.yMMMEd().format(d);
}
