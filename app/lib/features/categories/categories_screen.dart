import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(tabs: [Tab(text: 'Expenses'), Tab(text: 'Income')]),
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            tooltip: 'New category',
            onPressed: () {
              final kind = DefaultTabController.of(context).index == 0 ? TxType.expense : TxType.income;
              showCategoryDialog(context, ref, kind: kind);
            },
            child: const Icon(Icons.add),
          ),
        ),
        body: AsyncView(
          value: ref.watch(categoriesProvider),
          onRetry: () => ref.invalidate(categoriesProvider),
          builder: (categories) => TabBarView(children: [
            for (final kind in [TxType.expense, TxType.income])
              _CategoryList(categories: categories.where((c) => c.kind == kind).toList()),
          ]),
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (categories.isEmpty) {
      return const EmptyState(icon: Icons.category_outlined, title: 'No categories yet');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        ContentWidth(
          maxWidth: 700,
          child: Card(
            child: Column(children: [
              for (final c in categories)
                ListTile(
                  leading: IconBadge(icon: c.icon, color: c.color),
                  title: Text(c.name),
                  subtitle: c.isArchived ? const Text('Archived') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showCategoryDialog(context, ref, existing: c, kind: c.kind),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

Future<void> showCategoryDialog(BuildContext context, WidgetRef ref, {Category? existing, required TxType kind}) {
  final name = TextEditingController(text: existing?.name ?? '');
  var color = existing?.color ?? 0xFF0EA5E9;
  var icon = existing?.icon ?? 'category';
  var archived = existing?.isArchived ?? false;
  final formKey = GlobalKey<FormState>();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(existing == null ? 'New ${kind.label.toLowerCase()} category' : 'Edit category'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                  controller: name,
                  autofocus: existing == null,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconBadge(icon: icon, color: color, size: 28),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 8),
                ColorPickerRow(selected: color, onChanged: (c) => setState(() => color = c)),
                const SizedBox(height: 16),
                IconPickerGrid(selected: icon, color: color, onChanged: (i) => setState(() => icon = i)),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Archived'),
                    value: archived,
                    onChanged: (v) => setState(() => archived = v),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(dialogContext,
                    title: 'Delete ${existing.name}?',
                    message: 'Categories that are used by transactions cannot be deleted — archive them instead.');
                if (!ok) return;
                try {
                  await ref.read(repositoryProvider).deleteCategory(existing.id);
                  ref.invalidate(categoriesProvider);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (e) {
                  if (dialogContext.mounted) showError(dialogContext, e);
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await ref.read(repositoryProvider).saveCategory(Category(
                      id: existing?.id ?? '',
                      name: name.text.trim(),
                      kind: kind,
                      icon: icon,
                      color: color,
                      isArchived: archived,
                    ));
                ref.invalidate(categoriesProvider);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (e) {
                if (dialogContext.mounted) showError(dialogContext, e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
