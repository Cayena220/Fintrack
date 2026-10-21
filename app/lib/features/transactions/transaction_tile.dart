import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/sync.dart';

class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.tx, this.showDate = false});

  final Transaction tx;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final accounts = ref.watch(accountMapProvider);
    final category = ref.watch(categoryMapProvider)[tx.categoryId];
    final account = accounts[tx.accountId];
    final pending = ref.watch(syncControllerProvider.select((s) => s.pendingIds.contains(tx.id)));

    final String title;
    final String icon;
    final int color;
    String subtitle;
    if (tx.type == TxType.transfer) {
      title = 'Transfer';
      icon = 'bank';
      color = 0xFF475569;
      subtitle = '${account?.name ?? '?'} → ${accounts[tx.toAccountId]?.name ?? '?'}';
    } else {
      title = category?.name ?? 'Uncategorized';
      icon = category?.icon ?? 'category';
      color = category?.color ?? 0xFF9CA3AF;
      subtitle = account?.name ?? '';
    }
    if (tx.note != null && tx.note!.isNotEmpty) subtitle = '$subtitle · ${tx.note}';
    if (showDate) subtitle = '${formatRelativeDay(tx.occurredOn)} · $subtitle';

    final muted = FinColors.of(context).inkMuted;
    return ListTile(
      onTap: () => context.push('/transaction', extra: tx),
      leading: IconBadge(icon: icon, color: color),
      title: Row(children: [
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        if (tx.recurringRuleId != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(Symbols.repeat_rounded, size: 16, color: muted, semanticLabel: 'Recurring'),
          ),
        if (pending)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Tooltip(
              message: 'Waiting to sync',
              child: Icon(Symbols.cloud_upload_rounded, size: 16, color: muted, semanticLabel: 'Waiting to sync'),
            ),
          ),
      ]),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      // Income green with +, expense ink with −, transfers unsigned.
      trailing: MoneyText(
        tx.amount,
        currency: currency,
        kind: switch (tx.type) {
          TxType.income => AmountKind.income,
          TxType.expense => AmountKind.expense,
          TxType.transfer => AmountKind.plain,
        },
      ),
    );
  }
}
