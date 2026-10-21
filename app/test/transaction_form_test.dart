import 'package:fintrack/data/models.dart';
import 'package:fintrack/data/providers.dart';
import 'package:fintrack/features/transactions/transaction_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _accounts = [
  Account(
    id: 'a1',
    name: 'Wallet',
    type: AccountType.cash,
    initialBalance: 0,
    balance: 0,
    color: 0xFF059669,
    icon: 'wallet',
    isArchived: false,
  ),
  Account(
    id: 'a2',
    name: 'Bank',
    type: AccountType.bank,
    initialBalance: 0,
    balance: 0,
    color: 0xFF2563EB,
    icon: 'bank',
    isArchived: false,
  ),
];

const _categories = [
  Category(id: 'c1', name: 'Food', kind: TxType.expense, icon: 'restaurant', color: 0xFFEA580C, isArchived: false),
  Category(id: 'c2', name: 'Salary', kind: TxType.income, icon: 'work', color: 0xFF059669, isArchived: false),
];

Widget _app({List<Account> accounts = _accounts}) => ProviderScope(
      overrides: [
        accountsProvider.overrideWith((ref) async => accounts),
        categoriesProvider.overrideWith((ref) async => _categories),
        currencyProvider.overrideWithValue('PHP'),
      ],
      child: const MaterialApp(home: TransactionFormScreen()),
    );

void main() {
  testWidgets('shows expense categories and switches with the type', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('New transaction'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Salary'), findsNothing);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
  });

  testWidgets('requires an amount greater than zero', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than zero'), findsNothing);
    await tester.ensureVisible(find.text('Add transaction'));
    await tester.pump();
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.ensureVisible(find.text('Add transaction'));
    await tester.pump();
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
  });

  testWidgets('a transfer asks for a destination account', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transfer'));
    await tester.pumpAndSettle();
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Category'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, '100');
    expect(find.text('Choose where the money goes'), findsNothing);
    await tester.ensureVisible(find.text('Add transaction'));
    await tester.pump();
    await tester.tap(find.text('Add transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where the money goes'), findsOneWidget);
  });

  testWidgets('asks for an account when there is none', (tester) async {
    await tester.pumpWidget(_app(accounts: const []));
    await tester.pumpAndSettle();

    expect(find.text('Add an account first'), findsOneWidget);
  });
}
