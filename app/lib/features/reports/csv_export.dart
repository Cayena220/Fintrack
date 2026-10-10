import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';

import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

/// Builds the CSV text for a list of transactions (pure; unit-tested).
String transactionsToCsv(
  List<Transaction> txs, {
  required Map<String, Account> accounts,
  required Map<String, Category> categories,
}) {
  final rows = <List<Object?>>[
    ['Date', 'Type', 'Amount', 'Account', 'To account', 'Category', 'Note'],
    for (final t in txs)
      [
        toDbDate(t.occurredOn),
        t.type.label,
        centsToDecimal(t.type == TxType.expense ? -t.amount : t.amount).toStringAsFixed(2),
        accounts[t.accountId]?.name ?? '',
        t.toAccountId == null ? '' : (accounts[t.toAccountId]?.name ?? ''),
        t.categoryId == null ? '' : (categories[t.categoryId]?.name ?? ''),
        t.note ?? '',
      ],
  ];
  return csv.encode(rows);
}

/// Fetches transactions in [from]..[to] and opens a Save As dialog.
/// Returns the saved path, or null if the user cancelled.
Future<String?> exportTransactionsCsv(
  FinanceRepository repo, {
  required DateTime from,
  required DateTime to,
  required Map<String, Account> accounts,
  required Map<String, Category> categories,
}) async {
  final txs = await repo.fetchTransactions(from: from, to: to, limit: 100000);
  final text = transactionsToCsv(txs, accounts: accounts, categories: categories);
  // UTF-8 BOM so Excel shows currency symbols and accents correctly.
  final bytes = utf8.encode('﻿$text');
  return FileSaver.instance.saveAs(
    name: 'fintrack_${toDbDate(from)}_to_${toDbDate(to)}',
    bytes: bytes,
    fileExtension: 'csv',
    mimeType: MimeType.csv,
  );
}
