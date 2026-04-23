import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/presentation/auth_controller.dart';
import '../data/suppliers_repository.dart';
import '../domain/supplier_record.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final _searchController = TextEditingController();
  late Future<List<SupplierRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SupplierRecord>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }
    return ref.read(suppliersRepositoryProvider).fetchSuppliers(session.token);
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
  }

  String _formatMoney(double value) {
    return NumberFormat.decimalPattern('ru').format(value.round());
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Yetkazib beruvchilar',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => _openSupplierDialog(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yetkazib beruvchi qo‘shish'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: 'Nomi yoki telefoni bo‘yicha qidirish...',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: FutureBuilder<List<SupplierRecord>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Yetkazib beruvchilar yuklanmadi: ${_formatError(snapshot.error!)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF8A8A),
                    ),
                  ),
                );
              }

              final suppliers = snapshot.data ?? const <SupplierRecord>[];
              final query = _searchController.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? suppliers
                  : suppliers.where((supplier) {
                      return supplier.name.toLowerCase().contains(query) ||
                          supplier.phone.toLowerCase().contains(query) ||
                          supplier.address.toLowerCase().contains(query);
                    }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'Yetkazib beruvchi topilmadi',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                );
              }

              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final supplier = filtered[index];
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF243B67),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF365285)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    supplier.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    supplier.phone.isEmpty
                                        ? 'Telefon kiritilmagan'
                                        : supplier.phone,
                                    style: const TextStyle(
                                      color: Color(0xFFCAD7F0),
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  if (supplier.address.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      supplier.address,
                                      style: const TextStyle(
                                        color: Color(0xFF9FB5DA),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () =>
                                  _openSupplierDialog(context, supplier: supplier),
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Tahrirlash'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFE53935),
                                minimumSize: const Size(50, 44),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: () => _confirmDelete(context, supplier),
                              child: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _StatsChip(
                              label: 'Jami kirim',
                              value: '${_formatMoney(supplier.stats.totalPurchase)} so‘m',
                            ),
                            _StatsChip(
                              label: 'To‘langan',
                              value: '${_formatMoney(supplier.stats.totalPaid)} so‘m',
                            ),
                            _StatsChip(
                              label: 'Qarz',
                              value: '${_formatMoney(supplier.stats.totalDebt)} so‘m',
                              tone: supplier.stats.totalDebt > 0
                                  ? const Color(0xFF7F1D1D)
                                  : const Color(0xFF1E3A5F),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openSupplierDialog(
    BuildContext context, {
    SupplierRecord? supplier,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SupplierDialog(supplier: supplier),
    );
    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SupplierRecord supplier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF17284B),
        title: const Text('O‘chirish'),
        content: Text(
          '"${supplier.name}" yetkazib beruvchisini o‘chirmoqchimisiz?',
        ),
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
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || !mounted) return;

    try {
      await ref.read(suppliersRepositoryProvider).deleteSupplier(
            token: session.token,
            id: supplier.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yetkazib beruvchi o‘chirildi')),
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_formatError(error))),
      );
    }
  }
}

class _StatsChip extends StatelessWidget {
  const _StatsChip({
    required this.label,
    required this.value,
    this.tone = const Color(0xFF1E3A5F),
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF365285)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9FB5DA),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SupplierDialog extends ConsumerStatefulWidget {
  const _SupplierDialog({this.supplier});

  final SupplierRecord? supplier;

  @override
  ConsumerState<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _openingBalanceController;
  String _currency = 'uzs';
  bool _saving = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.supplier?.name ?? '');
    _addressController = TextEditingController(
      text: widget.supplier?.address ?? '',
    );
    _phoneController = TextEditingController(text: widget.supplier?.phone ?? '');
    _openingBalanceController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  String _formatError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (error.message != null && error.message!.isNotEmpty) {
        return error.message!;
      }
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF17284B),
      title: Text(
        widget.supplier == null
            ? 'Yetkazib beruvchi qo‘shish'
            : 'Yetkazib beruvchini tahrirlash',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration:
                    const InputDecoration(labelText: 'Yetkazib beruvchi nomi'),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Nom kiriting' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Manzil'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _openingBalanceController,
                      decoration: const InputDecoration(
                        labelText: 'Boshlang‘ich qarz',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      items: const [
                        DropdownMenuItem(value: 'uzs', child: Text('SO‘M')),
                        DropdownMenuItem(value: 'usd', child: Text('USD')),
                      ],
                      onChanged: (value) =>
                          setState(() => _currency = value ?? 'uzs'),
                      decoration: const InputDecoration(labelText: 'Valyuta'),
                    ),
                  ),
                ],
              ),
              if (_errorText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorText,
                    style: const TextStyle(
                      color: Color(0xFFFF8A8A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Bekor qilish'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;

    setState(() {
      _saving = true;
      _errorText = '';
    });

    try {
      final repo = ref.read(suppliersRepositoryProvider);
      final openingBalance = double.tryParse(
            _openingBalanceController.text.replaceAll(',', '.').trim(),
          ) ??
          0;

      if (widget.supplier == null) {
        await repo.createSupplier(
          token: session.token,
          name: _nameController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          openingBalanceAmount: openingBalance,
          openingBalanceCurrency: _currency,
        );
      } else {
        await repo.updateSupplier(
          token: session.token,
          id: widget.supplier!.id,
          name: _nameController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          openingBalanceAmount: openingBalance,
          openingBalanceCurrency: _currency,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = _formatError(error);
      });
    }
  }
}
