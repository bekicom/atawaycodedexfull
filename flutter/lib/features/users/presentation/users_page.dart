import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../domain/app_user_record.dart';
import 'users_controller.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key, required this.canCreate});

  final bool canCreate;

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _searchController = TextEditingController();
  String _inlineError = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 46,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Qidirish...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (widget.canCreate)
              SizedBox(
                width: 180,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () => _openUserDialog(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Xodim qo\'shish'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_inlineError.isNotEmpty) ...[
          Text(
            _inlineError,
            style: const TextStyle(
              color: Color(0xFFFF8A8A),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: usersAsync.when(
            data: (users) {
              final query = _searchController.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? users
                  : users.where((user) {
                      final haystack = '${user.username} ${user.roleLabel}'
                          .toLowerCase();
                      return haystack.contains(query);
                    }).toList();

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF223D72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF345891)),
                ),
                child: Column(
                  children: [
                    const _UsersHeaderRow(),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Xodim topilmadi'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFF2F4B7F),
                                  ),
                              itemBuilder: (context, index) {
                                final user = filtered[index];
                                return _UsersDataRow(
                                  dark: index.isEven,
                                  user: user,
                                  canEdit: widget.canCreate,
                                  onEdit: () =>
                                      _openUserDialog(context, user: user),
                                  onDelete: () => _deleteUser(user),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                'Xatolik: $error',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openUserDialog(
    BuildContext context, {
    AppUserRecord? user,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UserDialog(user: user),
    );
  }

  Future<void> _deleteUser(AppUserRecord user) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Xodimni o\'chirish'),
          content: Text('"${user.username}" foydalanuvchisini o\'chirasizmi?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Bekor qilish'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                foregroundColor: Colors.white,
              ),
              child: const Text('O\'chirish'),
            ),
          ],
        );
      },
    );
    if (approved != true) return;

    final controller = ref.read(usersActionControllerProvider.notifier);
    await controller.deleteUser(id: user.id);
    final state = ref.read(usersActionControllerProvider);
    if (!mounted) return;
    setState(() {
      _inlineError = state.hasError ? controller.formatError(state.error!) : '';
    });
  }
}

class _UsersHeaderRow extends StatelessWidget {
  const _UsersHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF3A5D98),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 28, child: _UserHeaderCell('Login')),
          Expanded(flex: 18, child: _UserHeaderCell('Rol')),
          Expanded(flex: 30, child: _UserHeaderCell('Yaratilgan sana')),
          Expanded(flex: 24, child: _UserHeaderCell('Amallar')),
        ],
      ),
    );
  }
}

class _UserHeaderCell extends StatelessWidget {
  const _UserHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    );
  }
}

class _UsersDataRow extends StatelessWidget {
  const _UsersDataRow({
    required this.dark,
    required this.user,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final bool dark;
  final AppUserRecord user;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: dark ? const Color(0xFF203863) : const Color(0xFF1C325B),
      child: Row(
        children: [
          Expanded(flex: 28, child: _UserCell(user.username)),
          Expanded(flex: 18, child: _UserCell(user.roleLabel)),
          Expanded(flex: 30, child: _UserCell(_formatDateTime(user.createdAt))),
          Expanded(
            flex: 24,
            child: canEdit
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 190,
                      height: 38,
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: onEdit,
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Tahrirlash'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 48,
                            height: 38,
                            child: ElevatedButton(
                              onPressed: onDelete,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const _UserCell('-'),
          ),
        ],
      ),
    );
  }
}

class _UserCell extends StatelessWidget {
  const _UserCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.user});

  final AppUserRecord? user;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  String _role = 'cashier';

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.user?.username ?? '',
    );
    _role = widget.user?.role ?? 'cashier';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(usersActionControllerProvider);
    final controller = ref.read(usersActionControllerProvider.notifier);
    final error = actionState.hasError
        ? controller.formatError(actionState.error!)
        : null;

    return AlertDialog(
      backgroundColor: const Color(0xFF17284B),
      title: Text(widget.user == null ? 'Yangi xodim' : 'Xodimni tahrirlash'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Login (username)',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Username kiriting'
                    : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rol'),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'cashier', child: Text('Kassir')),
                ],
                onChanged: (value) =>
                    setState(() => _role = value ?? 'cashier'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.user == null
                      ? 'Parol'
                      : 'Yangi parol (ixtiyoriy)',
                  hintText: widget.user == null
                      ? 'kamida 4 belgi'
                      : 'O‘zgartirmaslik uchun bo‘sh qoldiring',
                ),
                validator: (value) {
                  if (widget.user == null && (value == null || value.isEmpty)) {
                    return 'Parol kiriting';
                  }
                  if (value != null && value.isNotEmpty && value.length < 4) {
                    return 'Parol kamida 4 belgidan iborat bo‘lsin';
                  }
                  return null;
                },
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
                      .read(usersActionControllerProvider.notifier)
                      .saveUser(
                        id: widget.user?.id,
                        username: _usernameController.text,
                        password: _passwordController.text,
                        role: _role,
                      );

                  if (!context.mounted) return;
                  if (!ref.read(usersActionControllerProvider).hasError) {
                    Navigator.of(context).pop();
                  }
                },
          child: Text(actionState.isLoading ? 'Saqlanmoqda...' : 'Saqlash'),
        ),
      ],
    );
  }
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd.MM.yyyy HH:mm').format(value.toLocal());
}
