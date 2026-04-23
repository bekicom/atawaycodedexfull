import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/category_record.dart';
import 'categories_controller.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Kategoriyalar',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _openCategoryDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Kategoriya qo‘shish'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Qidirish...',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: categoriesAsync.when(
            data: (categories) {
              final query = _searchController.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? categories
                  : categories
                        .where(
                          (category) =>
                              category.name.toLowerCase().contains(query),
                        )
                        .toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'Kategoriya topilmadi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final category = filtered[index];

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243B67),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF365285)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            category.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              _openCategoryDialog(context, category: category),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('edit'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            minimumSize: const Size(50, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () => _confirmDelete(context, category),
                          child: const Icon(Icons.delete_outline_rounded),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                'Xatolik: $error',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF8A8A),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCategoryDialog(
    BuildContext context, {
    CategoryRecord? category,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryDialog(category: category),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CategoryRecord category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF17284B),
        title: const Text('O‘chirish'),
        content: Text('"${category.name}" kategoriyasini o‘chirmoqchimisiz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Bekor qilish'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('O‘chirish'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await ref
        .read(categoriesActionControllerProvider.notifier)
        .removeCategory(category.id);
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.category});

  final CategoryRecord? category;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(categoriesActionControllerProvider);
    final controller = ref.read(categoriesActionControllerProvider.notifier);
    final error = actionState.hasError
        ? controller.formatError(actionState.error!)
        : null;

    return AlertDialog(
      backgroundColor: const Color(0xFF17284B),
      title: Text(
        widget.category == null
            ? 'Yangi kategoriya qo‘shish'
            : 'Kategoriyani edit qilish',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Kategoriya nomi'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Kategoriya nomi kerak'
                    : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error, style: const TextStyle(color: Color(0xFFFF8A8A))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: actionState.isLoading
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: actionState.isLoading
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;

                  await ref
                      .read(categoriesActionControllerProvider.notifier)
                      .saveCategory(
                        id: widget.category?.id,
                        name: _nameController.text,
                      );

                  if (!context.mounted) return;
                  if (!ref.read(categoriesActionControllerProvider).hasError) {
                    Navigator.of(context).pop();
                  }
                },
          child: Text(
            actionState.isLoading
                ? 'Saqlanmoqda...'
                : widget.category == null
                ? 'Saqlash'
                : 'Yangilash',
          ),
        ),
      ],
    );
  }
}
