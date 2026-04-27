import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../../../core/config/api_endpoint_store.dart';
import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category_record.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_record.dart';
import '../../expenses/presentation/expenses_section.dart';
import '../../products/presentation/products_section.dart';
import '../../returns/presentation/returns_section.dart';
import '../../cashier/presentation/cashier_page.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sales_history_record.dart';
import '../../sales/domain/variant_sales_insights_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';
import '../../shifts/data/shifts_repository.dart';
import '../../shifts/domain/shift_record.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier_record.dart';
import '../../users/presentation/users_page.dart';
import 'home_dashboard_section.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_overview.dart';

final dashboardOverviewProvider = FutureProvider<DashboardOverview>((
  ref,
) async {
  final session = ref.watch(authControllerProvider).valueOrNull;
  if (session == null) {
    throw Exception('Session topilmadi');
  }
  return ref.watch(dashboardRepositoryProvider).fetchOverview(session.token);
});

bool _isUnauthorizedError(Object error) {
  if (error is DioException) {
    return error.response?.statusCode == 401;
  }
  final text = error.toString().toLowerCase();
  return text.contains('401') || text.contains('unauthorized');
}

Uint8List? _decodeImageDataUrl(String value) {
  final text = value.trim();
  if (!text.startsWith('data:image/')) {
    return null;
  }
  final commaIndex = text.indexOf(',');
  if (commaIndex == -1) {
    return null;
  }
  try {
    return base64Decode(text.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

enum AdminSection {
  home('Bosh sahifa', Icons.home_outlined),
  users('Xodimlar', Icons.groups_2_outlined),
  products('Mahsulotlar', Icons.inventory_2_outlined),
  categories('Kategoriyalar', Icons.category_outlined),
  customers('Clientlar', Icons.people_outline),
  suppliers('Yetkazib beruvchilar', Icons.local_shipping_outlined),
  expenses('Xarajatlar', Icons.wallet_outlined),
  sales('Sotuv tarixi', Icons.history_outlined),
  returns('Qaytarib olish', Icons.assignment_return_outlined),
  settings('Sozlamalar', Icons.settings_outlined);

  const AdminSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  AdminSection _section = AdminSection.home;
  bool _sidebarVisible = true;
  bool _posCompactMode = false;
  bool _loadedLayoutMode = false;

  @override
  void initState() {
    super.initState();
    _loadLayoutMode();
  }

  Future<void> _loadLayoutMode() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || !mounted) return;
    try {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .fetchSettings(session.token);
      if (!mounted) return;
      setState(() {
        _posCompactMode = settings.posCompactMode;
        _sidebarVisible = !settings.posCompactMode;
        _loadedLayoutMode = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadedLayoutMode = true;
      });
    }
  }

  void _handleSettingsSaved(AppSettingsRecord settings) {
    if (!mounted) return;
    setState(() {
      _posCompactMode = settings.posCompactMode;
      if (settings.posCompactMode) {
        _sidebarVisible = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final role = session?.user.role.trim().toLowerCase() ?? '';
    final isAdmin = role == 'admin';
    final isCashier = role == 'cashier' || role == 'kassa';
    if (isCashier) {
      return const CashierPage();
    }

    if (!isAdmin && _section == AdminSection.users) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _section = AdminSection.home;
        });
      });
    }

    final isCompact = _posCompactMode;
    final sideWidth = _sidebarVisible ? (isCompact ? 220.0 : 260.0) : 0.0;

    final content = switch (_section) {
      AdminSection.home => const HomeDashboardSection(),
      AdminSection.users =>
        isAdmin
            ? const UsersPage(canCreate: true)
            : const _AccessDeniedSection(
                title: 'Xodimlar bo‘limi',
                message: 'Bu bo‘lim faqat admin uchun ochiladi.',
              ),
      AdminSection.products => const ProductsDirectContent(),
      AdminSection.categories => const _CategoriesDirectContent(),
      AdminSection.customers => const _CustomersDirectContent(),
      AdminSection.suppliers => const _SuppliersDirectContent(),
      AdminSection.expenses => const ExpensesDirectContent(),
      AdminSection.sales => const _SalesDirectContent(),
      AdminSection.returns => const ReturnsDirectContent(),
      AdminSection.settings => _SettingsDirectContent(
        onSettingsSaved: _handleSettingsSaved,
      ),
    };

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              width: sideWidth,
              child: _sidebarVisible
                  ? _Sidebar(
                      current: _section,
                      isAdmin: isAdmin,
                      onSelect: (section) => setState(() => _section = section),
                      onLogout: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                    )
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isCompact ? 10 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: FilledButton.tonal(
                            onPressed: () {
                              setState(() {
                                _sidebarVisible = !_sidebarVisible;
                              });
                            },
                            style: FilledButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: Icon(
                              _sidebarVisible
                                  ? Icons.menu_open_rounded
                                  : Icons.menu_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _section.label,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        if (!_loadedLayoutMode)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2E57),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF2F4B7F)),
                        ),
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({
    required this.current,
    required this.isAdmin,
    required this.onSelect,
    required this.onLogout,
  });

  final AdminSection current;
  final bool isAdmin;
  final ValueChanged<AdminSection> onSelect;
  final Future<void> Function() onLogout;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigationItems = <Widget>[
      _SidebarButton(
        label: AdminSection.home.label,
        icon: AdminSection.home.icon,
        active: widget.current == AdminSection.home,
        onTap: () => widget.onSelect(AdminSection.home),
      ),
      const SizedBox(height: 10),
      if (widget.isAdmin) ...[
        _SidebarButton(
          label: AdminSection.users.label,
          icon: AdminSection.users.icon,
          active: widget.current == AdminSection.users,
          onTap: () => widget.onSelect(AdminSection.users),
        ),
        const SizedBox(height: 10),
      ],
      _SidebarButton(
        label: AdminSection.products.label,
        icon: AdminSection.products.icon,
        active: widget.current == AdminSection.products,
        onTap: () => widget.onSelect(AdminSection.products),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.categories.label,
        icon: AdminSection.categories.icon,
        active: widget.current == AdminSection.categories,
        onTap: () => widget.onSelect(AdminSection.categories),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.customers.label,
        icon: AdminSection.customers.icon,
        active: widget.current == AdminSection.customers,
        onTap: () => widget.onSelect(AdminSection.customers),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.suppliers.label,
        icon: AdminSection.suppliers.icon,
        active: widget.current == AdminSection.suppliers,
        onTap: () => widget.onSelect(AdminSection.suppliers),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.expenses.label,
        icon: AdminSection.expenses.icon,
        active: widget.current == AdminSection.expenses,
        onTap: () => widget.onSelect(AdminSection.expenses),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.sales.label,
        icon: AdminSection.sales.icon,
        active: widget.current == AdminSection.sales,
        onTap: () => widget.onSelect(AdminSection.sales),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.returns.label,
        icon: AdminSection.returns.icon,
        active: widget.current == AdminSection.returns,
        onTap: () => widget.onSelect(AdminSection.returns),
      ),
      const SizedBox(height: 10),
      _SidebarButton(
        label: AdminSection.settings.label,
        icon: AdminSection.settings.icon,
        active: widget.current == AdminSection.settings,
        onTap: () => widget.onSelect(AdminSection.settings),
      ),
    ];

    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        color: Color(0xFF101C37),
        border: Border(right: BorderSide(color: Color(0xFF22365F))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text('DOKON', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: navigationItems,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: widget.onLogout,
              child: const Text('Chiqish'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessDeniedSection extends StatelessWidget {
  const _AccessDeniedSection({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF223D72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF345891)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 44,
              color: Color(0xFF9FB5DA),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFFB8C8E6),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuppliersDirectContent extends ConsumerStatefulWidget {
  const _SuppliersDirectContent();

  @override
  ConsumerState<_SuppliersDirectContent> createState() =>
      _SuppliersDirectContentState();
}

class _SuppliersDirectContentState
    extends ConsumerState<_SuppliersDirectContent> {
  static const int _pageSize = 15;
  late Future<List<dynamic>> _future;
  bool _saving = false;
  String _errorMessage = '';
  bool _redirecting = false;
  int _currentPage = 1;
  final _moneyFormat = NumberFormat.decimalPattern('en_US');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }
    final results = await Future.wait<dynamic>([
      ref.read(suppliersRepositoryProvider).fetchSuppliers(session.token),
      ref.read(settingsRepositoryProvider).fetchSettings(session.token),
    ]);
    return results;
  }

  Future<void> _reload() async {
    setState(() {
      _currentPage = 1;
      _future = _load();
    });
  }

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  String _formatMoney(double uzs, double usd) {
    final uzsText = '${_moneyFormat.format(uzs.round())} so\'m';
    if (usd > 0) {
      return '$uzsText | ${usd.toStringAsFixed(2)} \$';
    }
    return uzsText;
  }

  double _parseAmount(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
  }

  String _formatDisplayMoney(double amount, AppSettingsRecord settings) {
    if (settings.displayCurrency == 'usd' && settings.usdRate > 0) {
      return '${(amount / settings.usdRate).toStringAsFixed(2)} \$';
    }
    return '${_moneyFormat.format(amount.round())} so\'m';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd.MM.yyyy, HH:mm').format(value.toLocal());
  }

  String _formatShortDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd.MM HH:mm').format(value.toLocal());
  }

  String _paymentLabel(String value) {
    switch (value.toLowerCase()) {
      case 'naqd':
      case 'cash':
        return 'Naqd';
      case 'qarz':
      case 'debt':
        return 'Qarz';
      case 'qisman':
      case 'mixed':
        return 'Qisman';
      default:
        return value.isEmpty ? '-' : value;
    }
  }

  Future<void> _openSupplierDialog({SupplierRecord? supplier}) async {
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final addressController = TextEditingController(
      text: supplier?.address ?? '',
    );
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final openingBalanceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String currency = 'uzs';
    String localError = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17284B),
              title: Text(
                supplier == null
                    ? 'Yangi yetkazib beruvchi'
                    : 'Yetkazib beruvchini edit',
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Nomi'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Yetkazib beruvchi nomi kerak'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: 'Manzili'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Telefon'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: openingBalanceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Astatka qarz',
                          hintText: '0',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: currency,
                        decoration: const InputDecoration(labelText: 'Valyuta'),
                        items: const [
                          DropdownMenuItem(value: 'uzs', child: Text('SO\'M')),
                          DropdownMenuItem(value: 'usd', child: Text('USD')),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  currency = value ?? 'uzs';
                                });
                              },
                      ),
                      if (localError.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          localError,
                          style: const TextStyle(color: Color(0xFFFF8A8A)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Bekor qilish'),
                ),
                ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          setState(() {
                            _saving = true;
                            _errorMessage = '';
                          });
                          setLocalState(() {
                            localError = '';
                          });

                          try {
                            final session = ref
                                .read(authControllerProvider)
                                .valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }

                            final payload = (
                              name: nameController.text,
                              address: addressController.text,
                              phone: phoneController.text,
                              openingBalanceAmount: _parseAmount(
                                openingBalanceController.text,
                              ),
                              openingBalanceCurrency: currency,
                            );

                            if (supplier == null) {
                              await ref
                                  .read(suppliersRepositoryProvider)
                                  .createSupplier(
                                    token: session.token,
                                    name: payload.name,
                                    address: payload.address,
                                    phone: payload.phone,
                                    openingBalanceAmount:
                                        payload.openingBalanceAmount,
                                    openingBalanceCurrency:
                                        payload.openingBalanceCurrency,
                                  );
                            } else {
                              await ref
                                  .read(suppliersRepositoryProvider)
                                  .updateSupplier(
                                    token: session.token,
                                    id: supplier.id,
                                    name: payload.name,
                                    address: payload.address,
                                    phone: payload.phone,
                                    openingBalanceAmount:
                                        payload.openingBalanceAmount,
                                    openingBalanceCurrency:
                                        payload.openingBalanceCurrency,
                                  );
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            final message = error
                                .toString()
                                .replaceFirst('Exception: ', '')
                                .replaceAll(
                                  'DioException [bad response]: ',
                                  '',
                                );
                            setLocalState(() {
                              localError = message;
                            });
                          } finally {
                            if (mounted) {
                              setState(() {
                                _saving = false;
                              });
                            }
                          }
                        },
                  child: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
    phoneController.dispose();
    openingBalanceController.dispose();
  }

  Future<void> _deleteSupplier(SupplierRecord supplier) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Yetkazib beruvchini o‘chirish'),
          content: Text('"${supplier.name}" yetkazib beruvchini o‘chirasizmi?'),
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
              child: const Text('O‘chirish'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;

    try {
      setState(() {
        _saving = true;
        _errorMessage = '';
      });

      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) {
        throw Exception('Session topilmadi');
      }

      await ref
          .read(suppliersRepositoryProvider)
          .deleteSupplier(token: session.token, id: supplier.id);

      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceAll('DioException [bad response]: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openSupplierHistoryDialog({
    required SupplierRecord supplier,
    required AppSettingsRecord settings,
  }) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    final ledger = await ref
        .read(suppliersRepositoryProvider)
        .fetchLedger(token: session.token, id: supplier.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final sortedPurchases = [...ledger.purchases]
          ..sort(
            (a, b) => (b.purchasedAt ?? DateTime(2000)).compareTo(
              a.purchasedAt ?? DateTime(2000),
            ),
          );
        return Dialog(
          backgroundColor: const Color(0xFF17284B),
          insetPadding: const EdgeInsets.all(28),
          child: SizedBox(
            width: 1180,
            height: 760,
            child: Padding(
              padding: const EdgeInsets.all(18),
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
                              '${supplier.name} - Xaridlar tarixi',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${supplier.phone} | ${supplier.address}'),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _SummaryCard(
                        label: 'Jami kelish',
                        value: _formatMoney(
                          ledger.totals.totalPurchase,
                          ledger.totals.totalPurchaseUsd,
                        ),
                      ),
                      _SummaryCard(
                        label: 'Jami to\'langan',
                        value: _formatMoney(
                          ledger.totals.totalPaid,
                          ledger.totals.totalPaidUsd,
                        ),
                      ),
                      _SummaryCard(
                        label: 'Jami qarz',
                        value: _formatMoney(
                          ledger.totals.totalDebt,
                          ledger.totals.totalDebtUsd,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SupplierPurchasesTable(
                            purchases: sortedPurchases,
                            formatDate: _formatDate,
                            paymentLabel: _paymentLabel,
                            formatMoney: (amount) =>
                                _formatDisplayMoney(amount, settings),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'To\'lovlar tarixi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _SupplierPaymentsTable(
                            payments: ledger.payments,
                            formatDate: _formatDate,
                            formatMoney: (amount) =>
                                _formatDisplayMoney(amount, settings),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Yopish'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSupplierPaymentDialog({
    required SupplierRecord supplier,
    required AppSettingsRecord settings,
  }) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String currency = settings.displayCurrency;
    String paymentError = '';
    bool payLoading = false;

    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    SupplierLedgerRecord ledger = await ref
        .read(suppliersRepositoryProvider)
        .fetchLedger(token: session.token, id: supplier.id);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final totalDebt = ledger.totals.totalDebt;
            final totalPaid = ledger.totals.totalPaid;
            final totalPurchase = ledger.totals.totalPurchase;

            void setQuickAmount(double ratio) {
              final next = currency == 'usd' && settings.usdRate > 0
                  ? ((totalDebt * ratio) / settings.usdRate)
                  : (totalDebt * ratio);
              amountController.text = next % 1 == 0
                  ? next.toInt().toString()
                  : next.toStringAsFixed(2);
            }

            return Dialog(
              backgroundColor: const Color(0xFF17284B),
              insetPadding: const EdgeInsets.all(28),
              child: SizedBox(
                width: 980,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${supplier.name} - To\'lovlar',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 210,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF162949),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF325183),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Holat',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Jami kelish: ${_formatDisplayMoney(totalPurchase, settings)}',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Jami to\'langan: ${_formatDisplayMoney(totalPaid, settings)}',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Qolgan qarz: ${_formatDisplayMoney(totalDebt, settings)}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                constraints: const BoxConstraints(
                                  minHeight: 210,
                                ),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF162949),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFF325183),
                                  ),
                                ),
                                child: Form(
                                  key: formKey,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Qarz to\'lovi',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextFormField(
                                        controller: amountController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          labelText: 'To\'lov summasi',
                                        ),
                                        validator: (value) =>
                                            (double.tryParse(value ?? '') ??
                                                    0) <=
                                                0
                                            ? 'Summa kiriting'
                                            : null,
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child:
                                                DropdownButtonFormField<String>(
                                                  initialValue: currency,
                                                  decoration:
                                                      const InputDecoration(
                                                        labelText: 'Valyuta',
                                                      ),
                                                  items: const [
                                                    DropdownMenuItem(
                                                      value: 'uzs',
                                                      child: Text('SO\'M'),
                                                    ),
                                                    DropdownMenuItem(
                                                      value: 'usd',
                                                      child: Text('USD'),
                                                    ),
                                                  ],
                                                  onChanged: payLoading
                                                      ? null
                                                      : (value) {
                                                          setLocalState(() {
                                                            currency =
                                                                value ?? 'uzs';
                                                          });
                                                        },
                                                ),
                                          ),
                                          const SizedBox(width: 12),
                                          FilledButton.tonal(
                                            onPressed: payLoading
                                                ? null
                                                : () => setQuickAmount(0.25),
                                            child: const Text('25%'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.tonal(
                                            onPressed: payLoading
                                                ? null
                                                : () => setQuickAmount(0.5),
                                            child: const Text('50%'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.tonal(
                                            onPressed: payLoading
                                                ? null
                                                : () => setQuickAmount(1),
                                            child: const Text('100%'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: noteController,
                                        decoration: const InputDecoration(
                                          labelText: 'Izoh',
                                          hintText: 'Masalan: karta orqali',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 42,
                                        child: ElevatedButton.icon(
                                          onPressed: payLoading
                                              ? null
                                              : () async {
                                                  if (!formKey.currentState!
                                                      .validate()) {
                                                    return;
                                                  }
                                                  setLocalState(() {
                                                    payLoading = true;
                                                    paymentError = '';
                                                  });
                                                  try {
                                                    var amount = _parseAmount(
                                                      amountController.text,
                                                    );
                                                    if (currency == 'usd' &&
                                                        settings.usdRate > 0) {
                                                      amount *=
                                                          settings.usdRate;
                                                    }
                                                    await ref
                                                        .read(
                                                          suppliersRepositoryProvider,
                                                        )
                                                        .payDebt(
                                                          token: session.token,
                                                          id: supplier.id,
                                                          amount: amount,
                                                          note: noteController
                                                              .text,
                                                        );
                                                    ledger = await ref
                                                        .read(
                                                          suppliersRepositoryProvider,
                                                        )
                                                        .fetchLedger(
                                                          token: session.token,
                                                          id: supplier.id,
                                                        );
                                                    amountController.clear();
                                                    noteController.clear();
                                                    await _reload();
                                                    setLocalState(() {});
                                                  } catch (error) {
                                                    paymentError = error
                                                        .toString()
                                                        .replaceFirst(
                                                          'Exception: ',
                                                          '',
                                                        )
                                                        .replaceAll(
                                                          'DioException [bad response]: ',
                                                          '',
                                                        );
                                                    setLocalState(() {});
                                                  } finally {
                                                    setLocalState(() {
                                                      payLoading = false;
                                                    });
                                                  }
                                                },
                                          icon: const Icon(
                                            Icons.payments_rounded,
                                          ),
                                          label: Text(
                                            payLoading
                                                ? 'Saqlanmoqda...'
                                                : 'To\'lovni saqlash',
                                          ),
                                        ),
                                      ),
                                      if (paymentError.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                          paymentError,
                                          style: const TextStyle(
                                            color: Color(0xFFFF8A8A),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SupplierPaymentsTable(
                          payments: ledger.payments,
                          formatDate: _formatDate,
                          formatMoney: (amount) =>
                              _formatDisplayMoney(amount, settings),
                        ),
                        const SizedBox(height: 12),
                        _SupplierDebtRowsTable(
                          purchases: ledger.purchases
                              .where((item) => item.debtAmount > 0)
                              .toList(),
                          formatDate: _formatDate,
                          formatMoney: (amount) =>
                              _formatDisplayMoney(amount, settings),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Yopish'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    amountController.dispose();
    noteController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (_isUnauthorizedError(snapshot.error!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleUnauthorized();
            });
            return const Center(
              child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
            );
          }
          return Center(child: Text('Xatolik: ${snapshot.error}'));
        }

        final items =
            (snapshot.data?[0] as List<SupplierRecord>?) ??
            const <SupplierRecord>[];
        final settings =
            snapshot.data?[1] as AppSettingsRecord? ??
            AppSettingsRecord.fromJson(const {});
        final totalPages = items.isEmpty
            ? 1
            : (items.length / _pageSize).ceil();
        final safePage = _currentPage.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, items.length);
        final pagedItems = items.sublist(start, end);

        if (safePage != _currentPage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _currentPage = safePage;
              });
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Yetkazib beruvchilar ro‘yxati',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 300,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : () => _openSupplierDialog(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Yetkazib beruvchi qo‘shish'),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty) ...[
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Color(0xFFFF8A8A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (items.isEmpty)
              const Expanded(
                child: Center(child: Text('Yetkazib beruvchi topilmadi')),
              )
            else
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF203766),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF325183)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFF365892),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 18, child: Text('Nomi')),
                            Expanded(flex: 18, child: Text('Manzili')),
                            Expanded(flex: 14, child: Text('Telefon')),
                            Expanded(flex: 16, child: Text('Jami kelish')),
                            Expanded(flex: 16, child: Text('Jami to‘langan')),
                            Expanded(flex: 16, child: Text('Jami qarz')),
                            Expanded(flex: 26, child: Text('Amallar')),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: pagedItems.length,
                          separatorBuilder: (_, index) => const Divider(
                            height: 1,
                            color: Color(0xFF325183),
                          ),
                          itemBuilder: (context, index) {
                            final item = pagedItems[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              color: const Color(0xFF223A69),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    flex: 18,
                                    child: Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 18,
                                    child: Text(
                                      item.address.isEmpty ? '-' : item.address,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 14,
                                    child: Text(
                                      item.phone.isEmpty ? '-' : item.phone,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 16,
                                    child: Text(
                                      _formatMoney(
                                        item.stats.totalPurchase,
                                        item.stats.totalPurchaseUsd,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 16,
                                    child: Text(
                                      _formatMoney(
                                        item.stats.totalPaid,
                                        item.stats.totalPaidUsd,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 16,
                                    child: Text(
                                      _formatMoney(
                                        item.stats.totalDebt,
                                        item.stats.totalDebtUsd,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF9CFFB0),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 26,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 52,
                                          height: 38,
                                          child: ElevatedButton(
                                            onPressed: _saving
                                                ? null
                                                : () =>
                                                      _openSupplierPaymentDialog(
                                                        supplier: item,
                                                        settings: settings,
                                                      ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF1FA34A,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: const Text(
                                              '\$',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 18,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 92,
                                          height: 38,
                                          child: FilledButton.tonalIcon(
                                            onPressed: _saving
                                                ? null
                                                : () =>
                                                      _openSupplierHistoryDialog(
                                                        supplier: item,
                                                        settings: settings,
                                                      ),
                                            icon: const Icon(
                                              Icons.history_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Tarix'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 92,
                                          height: 38,
                                          child: FilledButton.tonalIcon(
                                            onPressed: _saving
                                                ? null
                                                : () => _openSupplierDialog(
                                                    supplier: item,
                                                  ),
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                              size: 16,
                                            ),
                                            label: const Text('Edit'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 52,
                                          height: 38,
                                          child: ElevatedButton(
                                            onPressed: _saving
                                                ? null
                                                : () => _deleteSupplier(item),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFE53935,
                                              ),
                                              foregroundColor: Colors.white,
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: const Icon(
                                              Icons.delete_rounded,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (items.length > _pageSize)
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          decoration: const BoxDecoration(
                            border: Border(
                              top: BorderSide(color: Color(0xFF325183)),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('Sahifa $safePage / $totalPages'),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 110,
                                height: 38,
                                child: FilledButton.tonal(
                                  onPressed: safePage > 1
                                      ? () {
                                          setState(() {
                                            _currentPage = safePage - 1;
                                          });
                                        }
                                      : null,
                                  child: const Text('Oldingi'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 110,
                                height: 38,
                                child: ElevatedButton(
                                  onPressed: safePage < totalPages
                                      ? () {
                                          setState(() {
                                            _currentPage = safePage + 1;
                                          });
                                        }
                                      : null,
                                  child: const Text('Keyingi'),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SettingsDirectContent extends ConsumerStatefulWidget {
  const _SettingsDirectContent({this.onSettingsSaved});

  final ValueChanged<AppSettingsRecord>? onSettingsSaved;

  @override
  ConsumerState<_SettingsDirectContent> createState() =>
      _SettingsDirectContentState();
}

class _SettingsDirectContentState
    extends ConsumerState<_SettingsDirectContent> {
  final _backendUrlController = TextEditingController();
  late Future<AppSettingsRecord> _future;
  bool _saving = false;
  bool _redirecting = false;
  String _errorMessage = '';
  AppSettingsRecord? _initialSettings;
  AppSettingsRecord? _form;
  String _initialBackendUrl = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  Future<AppSettingsRecord> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }
    final settings = await ref
        .read(settingsRepositoryProvider)
        .fetchSettings(session.token);
    final backendUrl = await ApiEndpointStore.loadBaseUrl();
    _initialSettings = settings;
    _form ??= settings;
    _initialBackendUrl = backendUrl;
    _backendUrlController.text = backendUrl;
    return settings;
  }

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  void _setForm(AppSettingsRecord next) {
    setState(() {
      _form = next;
    });
  }

  Future<void> _pickLogo() async {
    const typeGroup = XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final extension = file.name.toLowerCase().endsWith('.png')
        ? 'png'
        : file.name.toLowerCase().endsWith('.webp')
        ? 'webp'
        : 'jpeg';
    final encoded = base64Encode(bytes);
    final dataUrl = 'data:image/$extension;base64,$encoded';
    final current = _form;
    if (current == null) return;
    _setForm(
      current.copyWith(receipt: current.receipt.copyWith(logoUrl: dataUrl)),
    );
  }

  Future<void> _save() async {
    final current = _form;
    if (current == null) return;

    try {
      setState(() {
        _saving = true;
        _errorMessage = '';
      });

      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) {
        throw Exception('Session topilmadi');
      }

      final saved = await ref
          .read(settingsRepositoryProvider)
          .updateSettings(token: session.token, settings: current);
      final nextBackendUrl = ApiEndpointStore.normalize(
        _backendUrlController.text,
      );
      await ApiEndpointStore.saveBaseUrl(nextBackendUrl);
      ref.read(apiBaseUrlProvider.notifier).state = nextBackendUrl;

      setState(() {
        _initialSettings = saved;
        _form = saved;
        _initialBackendUrl = nextBackendUrl;
        _backendUrlController.text = nextBackendUrl;
      });
      widget.onSettingsSaved?.call(saved);
    } catch (error) {
      if (_isUnauthorizedError(error)) {
        await _handleUnauthorized();
        return;
      }
      if (!mounted) return;
      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceAll('DioException [bad response]: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _reset() {
    if (_initialSettings == null) return;
    setState(() {
      _form = _initialSettings;
      _backendUrlController.text = _initialBackendUrl;
      _errorMessage = '';
    });
  }

  Widget _buildReceiptCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: _saving ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: _saving ? null : (next) => onChanged(next ?? false),
            ),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(AppSettingsRecord form) {
    final fields = form.receipt.fields;
    final logoBytes = _decodeImageDataUrl(form.receipt.logoUrl);
    Widget metaRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$label:',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    Widget itemPreview({
      required int index,
      required String name,
      required String code,
      required String qty,
      required String price,
      required String total,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$index. $name',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text('[$code]'),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    fields.showItemUnitPrice ? '$qty x $price' : qty,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (fields.showItemLineTotal)
                  Text(
                    '= $total',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: 302,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E8F2)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF17284B), fontSize: 11.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fields.showLogo && form.receipt.logoUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              Center(
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 300,
                    maxHeight: 150,
                  ),
                  child: logoBytes != null
                      ? Image.memory(logoBytes, fit: BoxFit.contain)
                      : Image.network(
                          form.receipt.logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text('Logo ko‘rinmadi'),
                        ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            if (fields.showReceiptNumber) metaRow('Chek raqami', '000032'),
            if (fields.showDate) metaRow('Sana', '20.04.2026'),
            if (fields.showTime) metaRow('Vaqt', '18:20'),
            if (fields.showType) metaRow('Amal', 'sotuv'),
            if (fields.showShift) metaRow('Smena', '1'),
            if (fields.showCashier) metaRow('Kassir', 'kassa2'),
            if (fields.showPaymentType) metaRow('To\'lov', 'Naqd'),
            if (fields.showCustomer) metaRow('Mijoz', 'Test mijoz (+99890...)'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '----------------------------------------',
                textAlign: TextAlign.center,
              ),
            ),
            if (fields.showPaymentType) ...[
              const SizedBox(height: 2),
              metaRow('Naqd', '6 000'),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '----------------------------------------',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (fields.showItemsTable) ...[
              itemPreview(
                index: 1,
                name: 'Bolalar Noski',
                code: '1012',
                qty: '1',
                price: '6 000',
                total: '6 000',
              ),
              const Padding(
                padding: EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  '----------------------------------------',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (fields.showTotal)
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Jami summa:',
                    style: TextStyle(
                      color: Color(0xFF17284B),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '31 500 so\'m',
                    style: TextStyle(
                      color: Color(0xFF17284B),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                '----------------------------------------',
                textAlign: TextAlign.center,
              ),
            ),
            if (fields.showLegalText &&
                form.receipt.legalText.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Text(
                  form.receipt.legalText.trim(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (fields.showContactLine && form.receipt.contactLine.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  form.receipt.contactLine,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (fields.showFooter)
              Text(
                form.receipt.footer.isEmpty
                    ? 'XARIDINGIZ UCHUN RAHMAT'
                    : form.receipt.footer,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            if (fields.showPhoneNumber && form.receipt.phoneNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Tel: ${form.receipt.phoneNumber}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            if (fields.showFooter ||
                fields.showPhoneNumber ||
                fields.showContactLine ||
                fields.showLegalText) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '----------------------------------------',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodePreview(AppSettingsRecord form) {
    final barcodeFields = form.barcodeLabel.fields;
    final isLandscape = form.barcodeLabel.orientation == 'landscape';
    return Container(
      width: isLandscape ? 320 : 250,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.black, fontSize: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (barcodeFields.showName)
              const Text(
                'TEST MAHSULOT',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            if (barcodeFields.showModel)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Model: PREMIUM'),
              ),
            if (barcodeFields.showCategory)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Kategoriya: OYINCHOQ'),
              ),
            if (barcodeFields.showBarcode)
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: double.infinity,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8E8E8),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '2427000098116',
                  style: TextStyle(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (barcodeFields.showPrice)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Narx: 25 000 so\'m',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppSettingsRecord>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (_isUnauthorizedError(snapshot.error!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleUnauthorized();
            });
            return const Center(
              child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
            );
          }
          return Center(child: Text('Xatolik: ${snapshot.error}'));
        }

        final form = _form ?? snapshot.data!;
        final fields = form.receipt.fields;
        final barcodeLabel = form.barcodeLabel;
        final barcodeFields = barcodeLabel.fields;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsCard(
                title: 'Displey rejimi',
                icon: Icons.monitor_outlined,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'POS 4:3 rejimi (compact) — yoqilsa sidebar default yopiq bo\'ladi va jadval uchun ko\'proq joy qoladi.',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Switch(
                      value: form.posCompactMode,
                      onChanged: _saving
                          ? null
                          : (value) {
                              _setForm(form.copyWith(posCompactMode: value));
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SettingsCard(
                      title: 'Umumiy sozlamalar',
                      icon: Icons.tune_outlined,
                      child: Column(
                        children: [
                          _SettingsRow(
                            label: 'Kam qolgan mahsulot chegarasi (dona)',
                            child: SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: form.lowStockThreshold.toString(),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  _setForm(
                                    form.copyWith(
                                      lowStockThreshold:
                                          int.tryParse(value) ??
                                          form.lowStockThreshold,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          _SettingsRow(
                            label: 'USD kursi (1\$ = so\'m)',
                            child: SizedBox(
                              width: 120,
                              child: TextFormField(
                                initialValue: form.usdRate.toStringAsFixed(0),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (value) {
                                  _setForm(
                                    form.copyWith(
                                      usdRate:
                                          double.tryParse(value) ??
                                          form.usdRate,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          _SettingsRow(
                            label: 'Dastur valyutasi',
                            child: SizedBox(
                              width: 120,
                              child: DropdownButtonFormField<String>(
                                initialValue: form.displayCurrency,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'uzs',
                                    child: Text('SO\'M'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'usd',
                                    child: Text('USD'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        _setForm(
                                          form.copyWith(
                                            displayCurrency: value == 'usd'
                                                ? 'usd'
                                                : 'uzs',
                                          ),
                                        );
                                      },
                              ),
                            ),
                          ),
                          _SettingsRow(
                            label: 'Ekran klaviaturasini yoqish bo\'lim',
                            child: Switch(
                              value: form.keyboardEnabled,
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      _setForm(
                                        form.copyWith(keyboardEnabled: value),
                                      );
                                    },
                            ),
                          ),
                          _SettingsRow(
                            label: 'Backend API manzili',
                            child: SizedBox(
                              width: 320,
                              child: TextFormField(
                                controller: _backendUrlController,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                  hintText: 'http://127.0.0.1:4000/api',
                                ),
                              ),
                            ),
                          ),
                          _SettingsRow(
                            label: 'Qo‘shimcha razmer/rang statistikasi',
                            child: Switch(
                              value: form.variantInsightsEnabled,
                              onChanged: _saving
                                  ? null
                                  : (value) {
                                      _setForm(
                                        form.copyWith(
                                          variantInsightsEnabled: value,
                                        ),
                                      );
                                    },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _SettingsCard(
                      title: 'Chek sozlamalari',
                      icon: Icons.download_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _SettingsField(
                                label: 'Chek pastki matni',
                                width: 340,
                                child: TextFormField(
                                  initialValue: form.receipt.footer,
                                  onChanged: (value) {
                                    _setForm(
                                      form.copyWith(
                                        receipt: form.receipt.copyWith(
                                          footer: value,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _SettingsField(
                                label: 'Chek qo\'shimcha matni',
                                width: 700,
                                child: TextFormField(
                                  initialValue: form.receipt.legalText,
                                  minLines: 4,
                                  maxLines: 7,
                                  onChanged: (value) {
                                    _setForm(
                                      form.copyWith(
                                        receipt: form.receipt.copyWith(
                                          legalText: value,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _SettingsField(
                                label: 'Telefon raqami',
                                width: 340,
                                child: TextFormField(
                                  initialValue: form.receipt.phoneNumber,
                                  onChanged: (value) {
                                    _setForm(
                                      form.copyWith(
                                        receipt: form.receipt.copyWith(
                                          phoneNumber: value,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _SettingsField(
                                label: 'Aloqa matni (ixtiyoriy)',
                                width: 340,
                                child: TextFormField(
                                  initialValue: form.receipt.contactLine,
                                  onChanged: (value) {
                                    _setForm(
                                      form.copyWith(
                                        receipt: form.receipt.copyWith(
                                          contactLine: value,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _SettingsField(
                                label: 'Logo URL (ixtiyoriy)',
                                width: 340,
                                child: TextFormField(
                                  initialValue: form.receipt.logoUrl,
                                  onChanged: (value) {
                                    _setForm(
                                      form.copyWith(
                                        receipt: form.receipt.copyWith(
                                          logoUrl: value,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              _SettingsField(
                                label: 'Kompyuterdan logo yuklash',
                                width: 340,
                                child: SizedBox(
                                  height: 48,
                                  child: OutlinedButton.icon(
                                    onPressed: _saving ? null : _pickLogo,
                                    icon: const Icon(
                                      Icons.upload_file_outlined,
                                    ),
                                    label: const Text('Fayl tanlash'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Chekda ko‘rinadigan maydonlar',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 20,
                            runSpacing: 2,
                            children: [
                              _buildReceiptCheckbox(
                                label: 'Logo',
                                value: fields.showLogo,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showLogo: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Chek raqami',
                                value: fields.showReceiptNumber,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showReceiptNumber: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Sana',
                                value: fields.showDate,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showDate: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Vaqt',
                                value: fields.showTime,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showTime: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Amal turi',
                                value: fields.showType,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showType: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Smena',
                                value: fields.showShift,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showShift: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Kassir',
                                value: fields.showCashier,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showCashier: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'To\'lov turi',
                                value: fields.showPaymentType,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showPaymentType: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Mijoz',
                                value: fields.showCustomer,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showCustomer: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Mahsulotlar jadvali',
                                value: fields.showItemsTable,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showItemsTable: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Mahsulot narxi ustuni',
                                value: fields.showItemUnitPrice,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showItemUnitPrice: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Mahsulot summa ustuni',
                                value: fields.showItemLineTotal,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showItemLineTotal: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Jami summa',
                                value: fields.showTotal,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(showTotal: value),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Pastki matn',
                                value: fields.showFooter,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showFooter: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Qo\'shimcha matn',
                                value: fields.showLegalText,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showLegalText: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Aloqa matni',
                                value: fields.showContactLine,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showContactLine: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildReceiptCheckbox(
                                label: 'Telefon',
                                value: fields.showPhoneNumber,
                                onChanged: (value) => _setForm(
                                  form.copyWith(
                                    receipt: form.receipt.copyWith(
                                      fields: fields.copyWith(
                                        showPhoneNumber: value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Test chek',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildPreview(form),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Shtixkod chop etish sozlamalari',
                icon: Icons.qr_code_2_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _SettingsField(
                          label: 'Label o\'lchami',
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'barcode-size-${barcodeLabel.paperSize}',
                            ),
                            initialValue: barcodeLabel.paperSize,
                            items: const [
                              DropdownMenuItem(
                                value: '58x40',
                                child: Text('58 x 40 mm'),
                              ),
                              DropdownMenuItem(
                                value: '60x40',
                                child: Text('60 x 40 mm'),
                              ),
                              DropdownMenuItem(
                                value: '70x50',
                                child: Text('70 x 50 mm'),
                              ),
                              DropdownMenuItem(
                                value: '80x50',
                                child: Text('80 x 50 mm'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    _setForm(
                                      form.copyWith(
                                        barcodeLabel: barcodeLabel.copyWith(
                                          paperSize: value ?? '58x40',
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                        _SettingsField(
                          label: 'Har chop etishda nusxa soni',
                          width: 260,
                          child: TextFormField(
                            initialValue: barcodeLabel.copies.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              _setForm(
                                form.copyWith(
                                  barcodeLabel: barcodeLabel.copyWith(
                                    copies: parsed != null && parsed > 0
                                        ? parsed
                                        : 1,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _SettingsField(
                          label: 'Yo\'nalish',
                          width: 260,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(
                              'barcode-orientation-${barcodeLabel.orientation}',
                            ),
                            initialValue: barcodeLabel.orientation,
                            items: const [
                              DropdownMenuItem(
                                value: 'portrait',
                                child: Text('Kitob'),
                              ),
                              DropdownMenuItem(
                                value: 'landscape',
                                child: Text('Albom'),
                              ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    _setForm(
                                      form.copyWith(
                                        barcodeLabel: barcodeLabel.copyWith(
                                          orientation: value ?? 'portrait',
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Shtixkodda ko\'rinadigan maydonlar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 20,
                      runSpacing: 2,
                      children: [
                        _buildReceiptCheckbox(
                          label: 'Mahsulot nomi',
                          value: barcodeFields.showName,
                          onChanged: (value) => _setForm(
                            form.copyWith(
                              barcodeLabel: barcodeLabel.copyWith(
                                fields: barcodeFields.copyWith(showName: value),
                              ),
                            ),
                          ),
                        ),
                        _buildReceiptCheckbox(
                          label: 'Shtixkod raqami',
                          value: barcodeFields.showBarcode,
                          onChanged: (value) => _setForm(
                            form.copyWith(
                              barcodeLabel: barcodeLabel.copyWith(
                                fields: barcodeFields.copyWith(
                                  showBarcode: value,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildReceiptCheckbox(
                          label: 'Narx',
                          value: barcodeFields.showPrice,
                          onChanged: (value) => _setForm(
                            form.copyWith(
                              barcodeLabel: barcodeLabel.copyWith(
                                fields: barcodeFields.copyWith(
                                  showPrice: value,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildReceiptCheckbox(
                          label: 'Model',
                          value: barcodeFields.showModel,
                          onChanged: (value) => _setForm(
                            form.copyWith(
                              barcodeLabel: barcodeLabel.copyWith(
                                fields: barcodeFields.copyWith(
                                  showModel: value,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _buildReceiptCheckbox(
                          label: 'Kategoriya',
                          value: barcodeFields.showCategory,
                          onChanged: (value) => _setForm(
                            form.copyWith(
                              barcodeLabel: barcodeLabel.copyWith(
                                fields: barcodeFields.copyWith(
                                  showCategory: value,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Test shtixkod',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBarcodePreview(form),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Color(0xFFFF8A8A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 150,
                    height: 44,
                    child: FilledButton.tonal(
                      onPressed: _saving ? null : _reset,
                      child: const Text('Bekor qilish'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 210,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving ? 'Saqlanmoqda...' : 'Sozlamalarni saqlash',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SalesViewData {
  const _SalesViewData({
    required this.history,
    required this.settings,
    required this.shifts,
    required this.variantInsights,
  });

  final SalesHistoryRecord history;
  final AppSettingsRecord settings;
  final ShiftsListRecord shifts;
  final VariantSalesInsightsRecord variantInsights;
}

class _ShiftComputedTotals {
  const _ShiftComputedTotals({
    required this.totalSalesCount,
    required this.totalItemsCount,
    required this.totalAmount,
    required this.totalCash,
    required this.totalCard,
    required this.totalClick,
    required this.totalDebt,
  });

  final int totalSalesCount;
  final double totalItemsCount;
  final double totalAmount;
  final double totalCash;
  final double totalCard;
  final double totalClick;
  final double totalDebt;

  factory _ShiftComputedTotals.zero() {
    return const _ShiftComputedTotals(
      totalSalesCount: 0,
      totalItemsCount: 0,
      totalAmount: 0,
      totalCash: 0,
      totalCard: 0,
      totalClick: 0,
      totalDebt: 0,
    );
  }

  _ShiftComputedTotals addSale(SaleRecord sale) {
    final itemCount = sale.items.fold<double>(
      0,
      (sum, item) => sum + item.quantity,
    );
    return _ShiftComputedTotals(
      totalSalesCount: totalSalesCount + 1,
      totalItemsCount: totalItemsCount + itemCount,
      totalAmount: totalAmount + sale.totalAmount,
      totalCash: totalCash + sale.payments.cash,
      totalCard: totalCard + sale.payments.card,
      totalClick: totalClick + sale.payments.click,
      totalDebt: totalDebt + sale.debtAmount,
    );
  }
}

class _ShiftComputation {
  const _ShiftComputation({
    required this.totalsByShiftId,
    required this.saleToShiftId,
  });

  final Map<String, _ShiftComputedTotals> totalsByShiftId;
  final Map<String, String> saleToShiftId;
}

class _SalesDirectContent extends ConsumerStatefulWidget {
  const _SalesDirectContent();

  @override
  ConsumerState<_SalesDirectContent> createState() =>
      _SalesDirectContentState();
}

class _SalesDirectContentState extends ConsumerState<_SalesDirectContent> {
  static const int _pageSize = 20;

  late Future<_SalesViewData> _future;
  bool _redirecting = false;
  String _period = 'today';
  String _search = '';
  String _dateFrom = '';
  String _dateTo = '';
  String _cashierFilter = '';
  String _shiftFilter = '';
  String _sizeFilter = '';
  String _colorFilter = '';
  int _page = 1;
  final _moneyFormat = NumberFormat.decimalPattern('en_US');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SalesViewData> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }

    final salesFuture = ref
        .read(salesRepositoryProvider)
        .fetchSales(
          token: session.token,
          period: _period,
          from: _dateFrom,
          to: _dateTo,
          cashierUsername: _cashierFilter,
          shiftId: _shiftFilter,
        );
    final shiftsFuture = ref
        .read(shiftsRepositoryProvider)
        .fetchShifts(
          token: session.token,
          period: _period,
          from: _dateFrom,
          to: _dateTo,
          cashierUsername: _cashierFilter,
        );
    final variantInsightsFuture = ref
        .read(salesRepositoryProvider)
        .fetchVariantInsights(
          token: session.token,
          period: _period,
          from: _dateFrom,
          to: _dateTo,
          cashierUsername: _cashierFilter,
          shiftId: _shiftFilter,
          size: _sizeFilter,
          color: _colorFilter,
        );
    final settingsFuture = ref
        .read(settingsRepositoryProvider)
        .fetchSettings(session.token);
    final results = await Future.wait<dynamic>([
      salesFuture,
      settingsFuture,
      shiftsFuture,
      variantInsightsFuture,
    ]);
    return _SalesViewData(
      history: results[0] as SalesHistoryRecord,
      settings: results[1] as AppSettingsRecord,
      shifts: results[2] as ShiftsListRecord,
      variantInsights: results[3] as VariantSalesInsightsRecord,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  String _paymentLabel(String value) {
    switch (value.toLowerCase()) {
      case 'cash':
        return 'Naqd';
      case 'card':
        return 'UZCARD';
      case 'click':
        return 'HUMO';
      case 'mixed':
        return 'Aralash';
      case 'debt':
        return 'Qarzga';
      case 'debt_payment':
        return 'Qarz to‘lovi';
      default:
        return value.isEmpty ? '-' : value;
    }
  }

  String _formatMoney(double amount, AppSettingsRecord settings) {
    if (settings.displayCurrency == 'usd' && settings.usdRate > 0) {
      return '${(amount / settings.usdRate).toStringAsFixed(2)} \$';
    }
    return '${_moneyFormat.format(amount.round())} so\'m';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd.MM.yyyy, HH:mm').format(value.toLocal());
  }

  String _formatShortDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd.MM HH:mm').format(value.toLocal());
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _variantLabel(SaleItemRecord item) {
    final size = item.variantSize.trim();
    final color = item.variantColor.trim();
    if (size.isEmpty && color.isEmpty) return '-';
    if (size.isEmpty) return color;
    if (color.isEmpty) return size;
    return '$size / $color';
  }

  Future<void> _exportSalesHistoryExcel({
    required SalesHistoryRecord history,
    required AppSettingsRecord settings,
    required ShiftsListRecord shifts,
    required List<SaleRecord> visibleSales,
  }) async {
    final saveLocation = await getSaveLocation(
      suggestedName:
          'sotuv_tarixi_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xls',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xls']),
      ],
    );
    if (saveLocation == null) return;

    final shiftsById = {for (final shift in shifts.shifts) shift.id: shift};
    final shiftComputation = _computeShiftData(
      shifts: shifts.shifts,
      sales: visibleSales,
    );

    final totalVisibleAmount = visibleSales.fold<double>(
      0,
      (sum, sale) => sum + sale.totalAmount,
    );
    final totalVisibleCash = visibleSales.fold<double>(
      0,
      (sum, sale) => sum + sale.payments.cash,
    );
    final totalVisibleCard = visibleSales.fold<double>(
      0,
      (sum, sale) => sum + sale.payments.card,
    );
    final totalVisibleClick = visibleSales.fold<double>(
      0,
      (sum, sale) => sum + sale.payments.click,
    );
    final totalVisibleDebt = visibleSales.fold<double>(
      0,
      (sum, sale) => sum + sale.debtAmount,
    );
    final totalVisibleProfit = visibleSales.fold<double>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<double>(
            0,
            (itemSum, item) =>
                itemSum + (item.lineProfit - item.returnedProfit),
          ),
    );
    final totalVisibleItems = visibleSales.fold<double>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<double>(
            0,
            (itemSum, item) => itemSum + _leftQty(item),
          ),
    );
    final totalVisibleSaleCount = visibleSales.length;

    final shiftRows = shifts.shifts.map((shift) {
      final shiftSales = visibleSales.where((sale) {
        if (sale.shiftId == shift.id) return true;
        final inferredShiftId = shiftComputation.saleToShiftId[_saleComputationKey(
          sale,
        )];
        return inferredShiftId == shift.id;
      }).toList();
      final totals =
          shiftComputation.totalsByShiftId[shift.id] ??
          _ShiftComputedTotals.zero();
      final shiftProfit = shiftSales.fold<double>(
        0,
        (sum, sale) =>
            sum +
            sale.items.fold<double>(
              0,
              (itemSum, item) =>
                  itemSum + (item.lineProfit - item.returnedProfit),
            ),
      );
      return <String, String>{
        'Smena': shift.shiftNumber > 0 ? '#${shift.shiftNumber}' : '-',
        'Kassir': shift.cashierUsername,
        'Status': shift.isOpen ? 'Ochiq' : 'Yopiq',
        'Ochilgan': _formatDate(shift.openedAt),
        'Yopilgan': _formatDate(shift.closedAt),
        'Sotuvlar': totals.totalSalesCount.toString(),
        'Soni': totals.totalItemsCount.toStringAsFixed(0),
        'Naqd': _formatMoney(totals.totalCash, settings),
        'UZCARD': _formatMoney(totals.totalCard, settings),
        'HUMO': _formatMoney(totals.totalClick, settings),
        'Qarz': _formatMoney(totals.totalDebt, settings),
        'Jami': _formatMoney(totals.totalAmount, settings),
        'Foyda': _formatMoney(shiftProfit, settings),
      };
    }).toList();

    final saleRows = visibleSales.map((sale) {
      final resolvedShiftId = sale.shiftId.isNotEmpty
          ? sale.shiftId
          : (shiftComputation.saleToShiftId[_saleComputationKey(sale)] ?? '');
      final shift = resolvedShiftId.isEmpty ? null : shiftsById[resolvedShiftId];
      final isDebtPayment =
          sale.transactionType == 'debt_payment' ||
          sale.paymentType == 'debt_payment';
      final productText = isDebtPayment
          ? 'Qarz to‘lovi${sale.customerName.isNotEmpty ? ' (${sale.customerName})' : ''}'
          : sale.items.map((item) => item.productName).join(', ');
      final qtyText = isDebtPayment
          ? '-'
          : sale.items
                .map(
                  (item) =>
                      '${_leftQty(item).toStringAsFixed(0)}/${item.quantity.toStringAsFixed(0)} ${item.unit}${_variantLabel(item) == '-' ? '' : ' (${_variantLabel(item)})'}',
                )
                .join(', ');
      final saleProfit = isDebtPayment
          ? 0.0
          : sale.items.fold<double>(
              0,
              (sum, item) => sum + (item.lineProfit - item.returnedProfit),
            );
      final saleCost = isDebtPayment
          ? 0.0
          : (sale.totalAmount - saleProfit)
                .clamp(0, double.infinity)
                .toDouble();
      return <String, String>{
        'Sana': _formatDate(sale.createdAt),
        'Smena': sale.shiftNumber > 0 ? '#${sale.shiftNumber}' : '-',
        'Kassir': sale.cashierUsername,
        'Mahsulotlar': productText,
        'Soni': qtyText,
        'To\'lov': _paymentLabel(sale.paymentType),
        'Naqd': _formatMoney(sale.payments.cash, settings),
        'UZCARD': _formatMoney(sale.payments.card, settings),
        'HUMO': _formatMoney(sale.payments.click, settings),
        'Qarz': _formatMoney(sale.debtAmount, settings),
        'Tannarx': _formatMoney(saleCost, settings),
        'Tushum': _formatMoney(sale.totalAmount, settings),
        'Foyda': _formatMoney(saleProfit, settings),
        'Qaytgan': _formatMoney(sale.returnedAmount, settings),
        'Izoh': sale.note.isEmpty ? '-' : sale.note,
        'Shift': shift == null
            ? '-'
            : '#${shift.shiftNumber} | ${shift.cashierUsername}',
      };
    }).toList();

    final itemRows = <Map<String, String>>[];
    for (final sale in visibleSales) {
      final shift = sale.shiftId.isEmpty ? null : shiftsById[sale.shiftId];
      for (final item in sale.items) {
        itemRows.add({
          'Sana': _formatDate(sale.createdAt),
          'Smena': sale.shiftNumber > 0 ? '#${sale.shiftNumber}' : '-',
          'Kassir': sale.cashierUsername,
          'Mahsulot': item.productName,
          'Model': item.productModel.isEmpty ? '-' : item.productModel,
          'Shtixkod': item.barcode.isEmpty ? '-' : item.barcode,
          'Kategoriya': item.categoryName.isEmpty ? '-' : item.categoryName,
          'Razmer': item.variantSize.isEmpty ? '-' : item.variantSize,
          'Rang': item.variantColor.isEmpty ? '-' : item.variantColor,
          'Variant': _variantLabel(item),
          'Miqdor': item.quantity.toStringAsFixed(0),
          'Qaytgan': item.returnedQuantity.toStringAsFixed(0),
          'Birligi': item.unit,
          'Narxi': _formatMoney(item.unitPrice, settings),
          'Jami': _formatMoney(item.lineTotal, settings),
          'Qaytgan jami': _formatMoney(item.returnedTotal, settings),
          'Foyda': _formatMoney(
            item.lineProfit - item.returnedProfit,
            settings,
          ),
          'Shift': shift == null
              ? '-'
              : '#${shift.shiftNumber} | ${shift.cashierUsername}',
        });
      }
    }

    String tableFromRows(List<Map<String, String>> rows) {
      if (rows.isEmpty) {
        return '<p>Ma\'lumot topilmadi</p>';
      }
      final headers = rows.first.keys.toList();
      final thead = headers.map((h) => '<th>${_escapeHtml(h)}</th>').join();
      final body = rows.map((row) {
        final cells = headers
            .map((h) => '<td>${_escapeHtml(row[h] ?? '-')}</td>')
            .join();
        return '<tr>$cells</tr>';
      }).join();
      return '<table><thead><tr>$thead</tr></thead><tbody>$body</tbody></table>';
    }

    final html =
        '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    body { font-family: Arial, sans-serif; color: #1f2a44; }
    h1, h2, h3 { margin: 0 0 12px; }
    .meta { margin-bottom: 16px; }
    .meta-grid { display: grid; grid-template-columns: repeat(2, minmax(240px, 1fr)); gap: 8px 16px; margin-bottom: 18px; }
    .meta-grid div { padding: 8px 10px; background: #f2f5fb; border: 1px solid #d7e0ef; border-radius: 8px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 18px; }
    th, td { border: 1px solid #b9c6d8; padding: 7px 9px; text-align: left; vertical-align: top; }
    th { background: #3f5f99; color: white; }
    .section { margin-top: 20px; }
    .note { font-size: 12px; color: #60708f; margin-bottom: 8px; }
  </style>
</head>
<body>
  <h1>Sotuv tarixi</h1>
  <div class="meta">
    <div class="meta-grid">
      <div>Period: ${_escapeHtml(_period)}</div>
      <div>Qidiruv: ${_escapeHtml(_search.isEmpty ? '-' : _search)}</div>
      <div>Kassir: ${_escapeHtml(_cashierFilter.isEmpty ? 'Barcha kassalar' : _cashierFilter)}</div>
      <div>Smena: ${_escapeHtml(_shiftFilter.isEmpty ? 'Barcha smenalar' : _shiftFilter)}</div>
      <div>Dan: ${_escapeHtml(_dateFrom.isEmpty ? '-' : _dateFrom)}</div>
      <div>Gacha: ${_escapeHtml(_dateTo.isEmpty ? '-' : _dateTo)}</div>
      <div>Razmer: ${_escapeHtml(_sizeFilter.isEmpty ? 'Barcha razmerlar' : _sizeFilter)}</div>
      <div>Rang: ${_escapeHtml(_colorFilter.isEmpty ? 'Barcha ranglar' : _colorFilter)}</div>
    </div>
    <div class="meta-grid">
      <div>Jami savdo: ${_escapeHtml(totalVisibleSaleCount.toString())}</div>
      <div>Jami mahsulot soni: ${_escapeHtml(totalVisibleItems.toStringAsFixed(0))}</div>
      <div>Naqd: ${_escapeHtml(_formatMoney(totalVisibleCash, settings))}</div>
      <div>UZCARD: ${_escapeHtml(_formatMoney(totalVisibleCard, settings))}</div>
      <div>HUMO: ${_escapeHtml(_formatMoney(totalVisibleClick, settings))}</div>
      <div>Qarz: ${_escapeHtml(_formatMoney(totalVisibleDebt, settings))}</div>
      <div>Jami tushum: ${_escapeHtml(_formatMoney(totalVisibleAmount, settings))}</div>
      <div>Jami foyda: ${_escapeHtml(_formatMoney(totalVisibleProfit, settings))}</div>
    </div>
  </div>
  <div class="section">
    <h2>Smena bo‘yicha</h2>
    ${tableFromRows(shiftRows)}
  </div>
  <div class="section">
    <h2>Sotuvlar</h2>
    ${tableFromRows(saleRows)}
  </div>
  <div class="section">
    <h2>Sotilgan mahsulotlar</h2>
    ${tableFromRows(itemRows)}
  </div>
</body>
</html>
''';

    final bytes = Uint8List.fromList(utf8.encode(html));
    await File(saveLocation.path).writeAsBytes(bytes, flush: true);
  }

  double _leftQty(SaleItemRecord item) {
    return (item.quantity - item.returnedQuantity).clamp(0, double.infinity);
  }

  bool _isFullyReturned(SaleRecord sale) {
    if (sale.items.isEmpty) return false;
    return sale.items.every((item) => _leftQty(item) <= 0.0001);
  }

  String _saleComputationKey(SaleRecord sale) {
    return '${sale.id}|${sale.createdAt?.millisecondsSinceEpoch ?? 0}|${sale.paymentType}|${sale.totalAmount.toStringAsFixed(2)}';
  }

  bool _isSaleInShiftWindow(DateTime? saleAt, ShiftRecord shift) {
    if (saleAt == null || shift.openedAt == null) return false;
    final openedAt = shift.openedAt!;
    final closedAt = shift.closedAt ?? DateTime.now().add(const Duration(seconds: 1));
    return !saleAt.isBefore(openedAt) && !saleAt.isAfter(closedAt);
  }

  _ShiftComputation _computeShiftData({
    required List<ShiftRecord> shifts,
    required List<SaleRecord> sales,
  }) {
    final totalsByShiftId = <String, _ShiftComputedTotals>{
      for (final shift in shifts) shift.id: _ShiftComputedTotals.zero(),
    };
    final saleToShiftId = <String, String>{};
    final shiftsById = {for (final shift in shifts) shift.id: shift};
    final shiftsByCashier = <String, List<ShiftRecord>>{};
    for (final shift in shifts) {
      final cashierKey = shift.cashierUsername.trim().toLowerCase();
      shiftsByCashier.putIfAbsent(cashierKey, () => []).add(shift);
    }
    for (final value in shiftsByCashier.values) {
      value.sort((a, b) {
        final aOpened = a.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bOpened = b.openedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bOpened.compareTo(aOpened);
      });
    }

    for (final sale in sales) {
      if (sale.transactionType != 'sale') continue;

      ShiftRecord? matchedShift;
      if (sale.shiftId.isNotEmpty) {
        matchedShift = shiftsById[sale.shiftId];
      }

      if (matchedShift == null) {
        final cashierKey = sale.cashierUsername.trim().toLowerCase();
        final candidates = shiftsByCashier[cashierKey] ?? const <ShiftRecord>[];
        if (candidates.isNotEmpty && sale.createdAt != null) {
          final preferred = sale.shiftNumber > 0
              ? candidates.where((shift) => shift.shiftNumber == sale.shiftNumber).toList()
              : candidates;
          final pool = preferred.isNotEmpty ? preferred : candidates;
          for (final shift in pool) {
            if (_isSaleInShiftWindow(sale.createdAt, shift)) {
              matchedShift = shift;
              break;
            }
          }
        }
      }

      if (matchedShift == null) continue;
      final saleKey = _saleComputationKey(sale);
      saleToShiftId[saleKey] = matchedShift.id;
      final current = totalsByShiftId[matchedShift.id] ?? _ShiftComputedTotals.zero();
      totalsByShiftId[matchedShift.id] = current.addSale(sale);
    }

    return _ShiftComputation(
      totalsByShiftId: totalsByShiftId,
      saleToShiftId: saleToShiftId,
    );
  }

  Future<void> _showCashierShiftDialog({
    required BuildContext context,
    required String cashierUsername,
    required List<ShiftRecord> shifts,
    required AppSettingsRecord settings,
    required Map<String, _ShiftComputedTotals> totalsByShiftId,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: const Color(0xFF17284B),
          insetPadding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$cashierUsername smenalari',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Jami smena: ${shifts.length}',
                    style: const TextStyle(color: Color(0xFF9FB6E9)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: shifts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final shift = shifts[index];
                        final totals =
                            totalsByShiftId[shift.id] ??
                            _ShiftComputedTotals.zero();
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF223A69),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: shift.isOpen
                                  ? const Color(0xFF67D68B)
                                  : const Color(0xFF325183),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Smena #${shift.shiftNumber}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: shift.isOpen
                                          ? const Color(0x2238D96E)
                                          : const Color(0x224B689A),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      shift.isOpen ? 'Ochiq' : 'Yopilgan',
                                      style: TextStyle(
                                        color: shift.isOpen
                                            ? const Color(0xFF67D68B)
                                            : const Color(0xFFB8C8E8),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 18,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Boshlangan: ${_formatDate(shift.openedAt)}',
                                  ),
                                  Text(
                                    'Tugagan: ${_formatDate(shift.closedAt)}',
                                  ),
                                  Text('Savdo: ${totals.totalSalesCount}'),
                                  Text(
                                    'Tovarlar: ${totals.totalItemsCount.toStringAsFixed(0)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 18,
                                runSpacing: 8,
                                children: [
                                  Text(
                                    'Naqd: ${_formatMoney(totals.totalCash, settings)}',
                                  ),
                                  Text(
                                    'UZCARD: ${_formatMoney(totals.totalCard, settings)}',
                                  ),
                                  Text(
                                    'HUMO: ${_formatMoney(totals.totalClick, settings)}',
                                  ),
                                  Text(
                                    'Qarz: ${_formatMoney(totals.totalDebt, settings)}',
                                  ),
                                  Text(
                                    'Jami: ${_formatMoney(totals.totalAmount, settings)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SalesViewData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (_isUnauthorizedError(snapshot.error!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleUnauthorized();
            });
            return const Center(
              child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
            );
          }
          return Center(child: Text('Xatolik: ${snapshot.error}'));
        }

        final data = snapshot.data!;
        final settings = data.settings;
        final history = data.history;
        final shifts = data.shifts;
        final variantInsights = data.variantInsights;
        final shiftsById = {for (final shift in shifts.shifts) shift.id: shift};
        final groupedShifts = <String, List<ShiftRecord>>{};
        for (final shift in shifts.shifts) {
          groupedShifts.putIfAbsent(shift.cashierUsername, () => []).add(shift);
        }
        final cashierShiftGroups = groupedShifts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        final query = _search.trim().toLowerCase();
        final cashierOptions = {
          ...history.sales.map((sale) => sale.cashierUsername),
          ...shifts.shifts.map((shift) => shift.cashierUsername),
        }.where((item) => item.trim().isNotEmpty).toList()..sort();
        final selectedShiftExists =
            _shiftFilter.isEmpty ||
            shifts.shifts.any((shift) => shift.id == _shiftFilter);
        final shiftComputation = _computeShiftData(
          shifts: shifts.shifts,
          sales: history.sales,
        );
        final visibleSales = query.isEmpty
            ? history.sales
            : history.sales.where((sale) {
                final text = [
                  sale.cashierUsername,
                  sale.paymentType,
                  sale.customerName,
                  sale.note,
                  ...sale.items.map((item) => item.productName),
                ].join(' ').toLowerCase();
                return text.contains(query);
              }).toList();
        final totalPages = visibleSales.isEmpty
            ? 1
            : (visibleSales.length / _pageSize).ceil();
        final totalReturnedAmount = visibleSales.fold<double>(
          0,
          (sum, sale) => sum + sale.returnedAmount,
        );
        final safePage = _page.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, visibleSales.length);
        final pagedSales = visibleSales.sublist(start, end);
        if (!selectedShiftExists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _shiftFilter = '';
              });
            }
          });
        }

        if (safePage != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _page = safePage;
              });
            }
          });
        }

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFF),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Color(0xFF183153)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final option in const [
                  ('today', '1 kunlik'),
                  ('yesterday', 'Kecha'),
                  ('7d', '7 kun'),
                  ('30d', '30 kun'),
                  ('all', 'Hammasi'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _period == option.$1,
                    onSelected: (_) {
                      setState(() {
                        _period = option.$1;
                        _page = 1;
                      });
                      _reload();
                    },
                  ),
                SizedBox(
                  width: 170,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Qidirish...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                        _page = 1;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    value: _cashierFilter.isEmpty ? null : _cashierFilter,
                    decoration: const InputDecoration(labelText: 'Kassir'),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Barcha kassalar'),
                      ),
                      ...cashierOptions.map(
                        (cashier) => DropdownMenuItem<String>(
                          value: cashier,
                          child: Text(cashier),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _cashierFilter = value ?? '';
                        _shiftFilter = '';
                        _sizeFilter = '';
                        _colorFilter = '';
                        _page = 1;
                      });
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    value: _shiftFilter.isEmpty ? null : _shiftFilter,
                    decoration: const InputDecoration(labelText: 'Smena'),
                    selectedItemBuilder: (context) {
                      return [
                        const Text(
                          'Barcha smenalar',
                          overflow: TextOverflow.ellipsis,
                        ),
                        ...shifts.shifts.map(
                          (shift) => Text(
                            '#${shift.shiftNumber} | ${shift.cashierUsername}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ];
                    },
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Barcha smenalar'),
                      ),
                      ...shifts.shifts.map(
                        (shift) => DropdownMenuItem<String>(
                          value: shift.id,
                          child: Text(
                            '#${shift.shiftNumber} | ${shift.cashierUsername}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _shiftFilter = value ?? '';
                        _page = 1;
                      });
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: TextEditingController(text: _dateFrom)
                      ..selection = TextSelection.fromPosition(
                        TextPosition(offset: _dateFrom.length),
                      ),
                    decoration: const InputDecoration(labelText: 'Dan'),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate:
                            DateTime.tryParse(_dateFrom) ?? DateTime.now(),
                      );
                      if (picked == null) return;
                      setState(() {
                        _period = 'all';
                        _dateFrom = DateFormat('yyyy-MM-dd').format(picked);
                        _page = 1;
                      });
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: TextEditingController(text: _dateTo)
                      ..selection = TextSelection.fromPosition(
                        TextPosition(offset: _dateTo.length),
                      ),
                    decoration: const InputDecoration(labelText: 'Gacha'),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate:
                            DateTime.tryParse(_dateTo) ?? DateTime.now(),
                      );
                      if (picked == null) return;
                      setState(() {
                        _period = 'all';
                        _dateTo = DateFormat('yyyy-MM-dd').format(picked);
                        _page = 1;
                      });
                      _reload();
                    },
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await _exportSalesHistoryExcel(
                        history: history,
                        settings: settings,
                        shifts: shifts,
                        visibleSales: visibleSales,
                      );
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Excel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  label: 'Savdolar',
                  value: '${history.summary.totalSales}',
                  icon: Icons.receipt_long_rounded,
                  accent: const Color(0xFF1E62B7),
                ),
                _SummaryCard(
                  label: 'Kassaga tushgan',
                  value: _formatMoney(
                    history.summary.totalCollection,
                    settings,
                  ),
                  icon: Icons.account_balance_wallet_rounded,
                  accent: const Color(0xFF2CA857),
                ),
                _SummaryCard(
                  label: 'Vazvrat summasi',
                  value: _formatMoney(totalReturnedAmount, settings),
                  icon: Icons.assignment_return_rounded,
                  accent: const Color(0xFFE24A3B),
                ),
                _SummaryCard(
                  label: 'UZCARD',
                  value: _formatMoney(history.summary.totalCard, settings),
                  brand: _DashboardBrand.uzcard,
                ),
                _SummaryCard(
                  label: 'Naqd',
                  value: _formatMoney(history.summary.totalCash, settings),
                  icon: Icons.payments_rounded,
                  accent: const Color(0xFF2CA857),
                ),
                _SummaryCard(
                  label: 'HUMO',
                  value: _formatMoney(history.summary.totalClick, settings),
                  brand: _DashboardBrand.humo,
                ),
                _SummaryCard(
                  label: 'Tannarx / Foyda',
                  value:
                      '${_formatMoney(history.summary.totalExpense, settings)} / ${_formatMoney(history.summary.totalProfit, settings)}',
                  icon: Icons.query_stats_rounded,
                  accent: const Color(0xFF7D56F4),
                ),
                _SummaryCard(
                  label: 'Smenalar',
                  value: '${shifts.summary.totalShifts}',
                  icon: Icons.layers_rounded,
                  accent: const Color(0xFF1E62B7),
                ),
                _SummaryCard(
                  label: 'Ochiq / Yopiq',
                  value:
                      '${shifts.summary.openShifts} / ${shifts.summary.closedShifts}',
                  icon: Icons.sync_alt_rounded,
                  accent: const Color(0xFF4E647D),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (settings.variantInsightsEnabled) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD6E2F3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F2747),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Razmer va rang bo‘yicha sotuv statistikasi',
                            style: TextStyle(
                              color: Color(0xFF163E7C),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String>(
                            value: _sizeFilter.isEmpty ? null : _sizeFilter,
                            decoration: const InputDecoration(
                              labelText: 'Razmer',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Barcha razmer'),
                              ),
                              ...variantInsights.availableSizes.map(
                                (size) => DropdownMenuItem<String>(
                                  value: size,
                                  child: Text(size),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _sizeFilter = value ?? '';
                              });
                              _reload();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            value: _colorFilter.isEmpty ? null : _colorFilter,
                            decoration: const InputDecoration(
                              labelText: 'Rang',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Barcha ranglar'),
                              ),
                              ...variantInsights.availableColors.map(
                                (color) => DropdownMenuItem<String>(
                                  value: color,
                                  child: Text(color),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _colorFilter = value ?? '';
                              });
                              _reload();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SummaryCard(
                          label: 'Variant savdo soni',
                          value: variantInsights.summary.totalQuantity
                              .toStringAsFixed(0),
                        ),
                        _SummaryCard(
                          label: 'Variant tushumi',
                          value: _formatMoney(
                            variantInsights.summary.totalRevenue,
                            settings,
                          ),
                        ),
                        _SummaryCard(
                          label: 'Ko‘p sotilgan kiyim',
                          value:
                              variantInsights.summary.topProduct.label.isEmpty
                              ? '-'
                              : variantInsights.summary.topProduct.label,
                        ),
                        _SummaryCard(
                          label: 'Ko‘p sotilgan razmer',
                          value: variantInsights.summary.topSize.label.isEmpty
                              ? '-'
                              : '${variantInsights.summary.topSize.label} (${variantInsights.summary.topSize.quantity.toStringAsFixed(0)})',
                        ),
                        _SummaryCard(
                          label: 'Ko‘p sotilgan rang',
                          value: variantInsights.summary.topColor.label.isEmpty
                              ? '-'
                              : '${variantInsights.summary.topColor.label} (${variantInsights.summary.topColor.quantity.toStringAsFixed(0)})',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD6E2F3)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFF365892),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(14),
                                topRight: Radius.circular(14),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 18, child: Text('Kiyim')),
                                Expanded(flex: 8, child: Text('Razmer')),
                                Expanded(flex: 10, child: Text('Rang')),
                                Expanded(flex: 8, child: Text('Soni')),
                                Expanded(flex: 10, child: Text('Tushum')),
                              ],
                            ),
                          ),
                          if (variantInsights.rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                'Tanlangan filter bo‘yicha razmer/rang savdosi topilmadi',
                              ),
                            )
                          else
                            ...variantInsights.rows
                                .take(8)
                                .map(
                                  (row) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: Color(0xFF325183),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 18,
                                          child: Text(
                                            row.productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 8,
                                          child: Text(
                                            row.size.isEmpty ? '-' : row.size,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 10,
                                          child: Text(
                                            row.color.isEmpty ? '-' : row.color,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 8,
                                          child: Text(
                                            row.quantity.toStringAsFixed(0),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 10,
                                          child: Text(
                                            _formatMoney(row.revenue, settings),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD6E2F3)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x120F2747),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Smena hisobotlari',
                    style: TextStyle(
                      color: Color(0xFF163E7C),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (shifts.shifts.isEmpty)
                    const Text('Smena topilmadi')
                  else
                    SizedBox(
                      height: 168,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: cashierShiftGroups.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final entry = cashierShiftGroups[index];
                          final cashier = entry.key;
                          final cashierShifts = entry.value;
                          final totalAmount = cashierShifts.fold<double>(
                            0,
                            (sum, shift) =>
                                sum +
                                (shiftComputation.totalsByShiftId[shift.id]
                                        ?.totalAmount ??
                                    0),
                          );
                          final totalSales = cashierShifts.fold<int>(
                            0,
                            (sum, shift) =>
                                sum +
                                (shiftComputation.totalsByShiftId[shift.id]
                                        ?.totalSalesCount ??
                                    0),
                          );
                          final openCount = cashierShifts
                              .where((shift) => shift.isOpen)
                              .length;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _showCashierShiftDialog(
                              context: context,
                              cashierUsername: cashier,
                              shifts: cashierShifts,
                              settings: settings,
                              totalsByShiftId: shiftComputation.totalsByShiftId,
                            ),
                            child: Container(
                              width: 250,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FBFF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: openCount > 0
                                      ? const Color(0xFF67D68B)
                                      : const Color(0xFFD6E2F3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cashier,
                                    style: const TextStyle(
                                      color: Color(0xFF183153),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Smenalar: ${cashierShifts.length}'),
                                  Text('Ochiq smena: $openCount'),
                                  Text('Savdolar: $totalSales'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Jami tushum: ${_formatMoney(totalAmount, settings)}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  const Text(
                                    'Batafsil ko‘rish',
                                    style: TextStyle(
                                      color: Color(0xFF6F87A7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD6E2F3)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x120F2747),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF184384),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: const DefaultTextStyle(
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Row(
                          children: [
                          Expanded(flex: 14, child: Text('Sana')),
                          Expanded(flex: 8, child: Text('Smena')),
                          Expanded(flex: 10, child: Text('Kassir')),
                          Expanded(flex: 18, child: Text('Mahsulotlar')),
                          Expanded(flex: 12, child: Text('Soni')),
                          Expanded(flex: 10, child: Text('To‘lov')),
                          Expanded(flex: 9, child: Text('Naqd')),
                          Expanded(flex: 9, child: Text('UZCARD')),
                          Expanded(flex: 9, child: Text('HUMO')),
                          Expanded(flex: 9, child: Text('Qarz')),
                          Expanded(flex: 9, child: Text('Tannarx')),
                          Expanded(flex: 9, child: Text('Tushum')),
                          Expanded(flex: 9, child: Text('Foyda')),
                        ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: pagedSales.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    size: 42,
                                    color: Color(0xFF9EB1CB),
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'Sotuv topilmadi',
                                    style: TextStyle(
                                      color: Color(0xFF6A7E9E),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: pagedSales.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFFDCE7F4),
                                  ),
                              itemBuilder: (context, index) {
                                final sale = pagedSales[index];
                                final resolvedShiftId = sale.shiftId.isNotEmpty
                                    ? sale.shiftId
                                    : (shiftComputation.saleToShiftId[_saleComputationKey(
                                        sale,
                                      )] ??
                                      '');
                                final shift = resolvedShiftId.isEmpty
                                    ? null
                                    : shiftsById[resolvedShiftId];
                                final isDebtPayment =
                                    sale.transactionType == 'debt_payment' ||
                                    sale.paymentType == 'debt_payment';
                                final fullyReturned =
                                    !isDebtPayment && _isFullyReturned(sale);
                                final productText = isDebtPayment
                                    ? 'Qarz to‘lovi${sale.customerName.isNotEmpty ? ' (${sale.customerName})' : ''}'
                                    : sale.items
                                          .map((item) => item.productName)
                                          .join(', ');
                                final qtyText = isDebtPayment
                                    ? '-'
                                    : sale.items
                                          .map(
                                            (item) =>
                                                '${_leftQty(item).toStringAsFixed(0)}/${item.quantity.toStringAsFixed(0)} ${item.unit}',
                                          )
                                          .join(', ');
                                final saleProfit = isDebtPayment
                                    ? 0.0
                                    : sale.items.fold<double>(
                                        0,
                                        (sum, item) =>
                                            sum +
                                            (item.lineProfit -
                                                item.returnedProfit),
                                      );
                                final saleCost = isDebtPayment
                                    ? 0.0
                                    : (sale.totalAmount - saleProfit)
                                          .clamp(0, double.infinity)
                                          .toDouble();

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  color: fullyReturned
                                      ? const Color(0xFFFFF2F0)
                                      : Colors.white,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 14,
                                        child: Text(
                                          _formatDate(sale.createdAt),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 8,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sale.shiftNumber > 0
                                                  ? '#${sale.shiftNumber}'
                                                  : '-',
                                            ),
                                            if (shift != null)
                                              Text(
                                                '${_formatShortDate(shift.openedAt)} - ${_formatShortDate(shift.closedAt)}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF7D8FA8),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 10,
                                        child: Text(sale.cashierUsername),
                                      ),
                                      Expanded(
                                        flex: 18,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(productText),
                                            if (fullyReturned)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                child: Text(
                                                  'Vozvrat qilindi',
                                                  style: TextStyle(
                                                    color: Color(0xFFD64545),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(flex: 12, child: Text(qtyText)),
                                      Expanded(
                                        flex: 10,
                                        child: Text(
                                          _paymentLabel(sale.paymentType),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(
                                            sale.payments.cash,
                                            settings,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(
                                            sale.payments.card,
                                            settings,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(
                                            sale.payments.click,
                                            settings,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(
                                            sale.debtAmount,
                                            settings,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(saleCost, settings),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(
                                            sale.totalAmount,
                                            settings,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 9,
                                        child: Text(
                                          _formatMoney(saleProfit, settings),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                    if (visibleSales.length > _pageSize)
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFDCE7F4)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('Sahifa $safePage / $totalPages'),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 110,
                              height: 38,
                              child: FilledButton.tonal(
                                onPressed: safePage > 1
                                    ? () {
                                        setState(() {
                                          _page = safePage - 1;
                                        });
                                      }
                                    : null,
                                child: const Text('Oldingi'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              height: 38,
                              child: ElevatedButton(
                                onPressed: safePage < totalPages
                                    ? () {
                                        setState(() {
                                          _page = safePage + 1;
                                        });
                                      }
                                    : null,
                                child: const Text('Keyingi'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _DashboardBrand { uzcard, humo }

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    this.icon,
    this.accent = const Color(0xFF1E62B7),
    this.brand,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color accent;
  final _DashboardBrand? brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 188,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD6E2F3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F2747),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DashboardStatBadge(
                brand: brand,
                accent: accent,
                icon: icon ?? Icons.circle,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF183153),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatBadge extends StatelessWidget {
  const _DashboardStatBadge({
    required this.icon,
    required this.accent,
    this.brand,
  });

  final IconData icon;
  final Color accent;
  final _DashboardBrand? brand;

  @override
  Widget build(BuildContext context) {
    if (brand == _DashboardBrand.humo) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F4FA),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(5),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset('assets/branding/humo_logo.png', fit: BoxFit.contain),
        ),
      );
    }

    if (brand == _DashboardBrand.uzcard) {
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF11489B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'U',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                height: 0.9,
              ),
            ),
            Text(
              'UZCARD',
              style: TextStyle(
                color: Color(0xFFFFC94E),
                fontSize: 5.5,
                fontWeight: FontWeight.w900,
                height: 0.9,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: accent, size: 20),
    );
  }
}

class _CustomersTable extends StatelessWidget {
  const _CustomersTable({
    required this.customers,
    required this.safePage,
    required this.pageSize,
    required this.totalPages,
    required this.totalItems,
    required this.formatMoney,
    required this.onEdit,
    required this.onOpenLedger,
    required this.onDelete,
    required this.onPrevPage,
    required this.onNextPage,
  });

  final List<CustomerRecord> customers;
  final int safePage;
  final int pageSize;
  final int totalPages;
  final int totalItems;
  final String Function(double amount) formatMoney;
  final void Function(CustomerRecord customer) onEdit;
  final void Function(CustomerRecord customer) onOpenLedger;
  final void Function(CustomerRecord customer) onDelete;
  final VoidCallback? onPrevPage;
  final VoidCallback? onNextPage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 6, child: Text('#')),
                Expanded(flex: 18, child: Text('Ism-familya')),
                Expanded(flex: 14, child: Text('Telefon')),
                Expanded(flex: 18, child: Text('Manzil')),
                Expanded(flex: 11, child: Text('Qarz')),
                Expanded(flex: 11, child: Text('To\'langan')),
                Expanded(flex: 24, child: Text('Amal')),
              ],
            ),
          ),
          Expanded(
            child: customers.isEmpty
                ? const Center(child: Text('Mijozlar topilmadi'))
                : ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: Color(0xFF325183)),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final rowIndex = (safePage - 1) * pageSize + index + 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        color: const Color(0xFF223A69),
                        child: Row(
                          children: [
                            Expanded(flex: 6, child: Text('$rowIndex')),
                            Expanded(
                              flex: 18,
                              child: Text(
                                customer.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 14,
                              child: Text(
                                customer.phone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 18,
                              child: Text(
                                customer.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 11,
                              child: Text(
                                formatMoney(customer.totalDebt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 11,
                              child: Text(
                                formatMoney(customer.totalPaid),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 24,
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Tooltip(
                                      message: 'Tahrirlash',
                                      child: FilledButton.tonal(
                                        onPressed: () => onEdit(customer),
                                        style: FilledButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(28, 28),
                                          maximumSize: const Size(28, 28),
                                        ),
                                        child: const Icon(
                                          Icons.edit_rounded,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Tooltip(
                                      message: 'Ko\'rish',
                                      child: OutlinedButton(
                                        onPressed: () => onOpenLedger(customer),
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(28, 28),
                                          maximumSize: const Size(28, 28),
                                        ),
                                        child: const Icon(
                                          Icons.visibility_rounded,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Tooltip(
                                      message: 'O\'chirish',
                                      child: ElevatedButton(
                                        onPressed: () => onDelete(customer),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFE53935,
                                          ),
                                          foregroundColor: Colors.white,
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(28, 28),
                                          maximumSize: const Size(28, 28),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (totalItems > pageSize)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF325183))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Sahifa $safePage / $totalPages'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    height: 38,
                    child: FilledButton.tonal(
                      onPressed: onPrevPage,
                      child: const Text('Oldingi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    height: 38,
                    child: ElevatedButton(
                      onPressed: onNextPage,
                      child: const Text('Keyingi'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerLedgerSalesTable extends StatelessWidget {
  const _CustomerLedgerSalesTable({
    required this.sortedSales,
    required this.formatDate,
    required this.formatMoney,
  });

  final List<CustomerLedgerSaleRecord> sortedSales;
  final String Function(DateTime? value) formatDate;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 14, child: Text('Sana')),
                Expanded(flex: 28, child: Text('Mahsulot')),
                Expanded(flex: 16, child: Text('Miqdor')),
                Expanded(flex: 12, child: Text('Jami')),
                Expanded(flex: 12, child: Text('To\'langan')),
                Expanded(flex: 12, child: Text('Qarz')),
              ],
            ),
          ),
          if (sortedSales.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Savdolar topilmadi'),
            )
          else
            ...sortedSales.map((sale) {
              final paid = (sale.totalAmount - sale.debtAmount)
                  .clamp(0, double.infinity)
                  .toDouble();
              final productText = sale.items.isNotEmpty
                  ? sale.items
                        .map(
                          (item) =>
                              '${item.productName} (${item.productModel.isEmpty ? '-' : item.productModel})',
                        )
                        .join(', ')
                  : (sale.note.isEmpty
                        ? 'Boshlang\'ich qarzdorlik'
                        : sale.note);
              final qtyText = sale.items.isNotEmpty
                  ? sale.items
                        .map(
                          (item) =>
                              '${item.quantity.toStringAsFixed(0)} ${item.unit}',
                        )
                        .join(', ')
                  : '-';
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF325183))),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 14, child: Text(formatDate(sale.createdAt))),
                    Expanded(flex: 28, child: Text(productText)),
                    Expanded(flex: 16, child: Text(qtyText)),
                    Expanded(
                      flex: 12,
                      child: Text(formatMoney(sale.totalAmount)),
                    ),
                    Expanded(flex: 12, child: Text(formatMoney(paid))),
                    Expanded(
                      flex: 12,
                      child: Text(
                        formatMoney(sale.debtAmount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _CustomerLedgerPaymentsTable extends StatelessWidget {
  const _CustomerLedgerPaymentsTable({
    required this.payments,
    required this.formatDate,
    required this.formatMoney,
  });

  final List<CustomerPaymentRecord> payments;
  final String Function(DateTime? value) formatDate;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 16, child: Text('Sana')),
                Expanded(flex: 12, child: Text('Summa')),
                Expanded(flex: 12, child: Text('Kim olgan')),
                Expanded(flex: 20, child: Text('Izoh')),
              ],
            ),
          ),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('To\'lovlar hali yo\'q'),
            )
          else
            ...payments.map(
              (payment) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF325183))),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 16, child: Text(formatDate(payment.paidAt))),
                    Expanded(
                      flex: 12,
                      child: Text(formatMoney(payment.amount)),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(
                        payment.cashierUsername.isEmpty
                            ? '-'
                            : payment.cashierUsername,
                      ),
                    ),
                    Expanded(
                      flex: 20,
                      child: Text(payment.note.isEmpty ? '-' : payment.note),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierPurchasesTable extends StatelessWidget {
  const _SupplierPurchasesTable({
    required this.purchases,
    required this.formatDate,
    required this.paymentLabel,
    required this.formatMoney,
  });

  final List<SupplierPurchaseRecord> purchases;
  final String Function(DateTime? value) formatDate;
  final String Function(String value) paymentLabel;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 15, child: Text('Sana')),
                Expanded(flex: 22, child: Text('Mahsulot')),
                Expanded(flex: 10, child: Text('Miqdor')),
                Expanded(flex: 12, child: Text('Jami')),
                Expanded(flex: 12, child: Text('To\'langan')),
                Expanded(flex: 12, child: Text('Qarz')),
                Expanded(flex: 10, child: Text('To\'lov')),
              ],
            ),
          ),
          if (purchases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Xaridlar topilmadi'),
            )
          else
            ...purchases.map(
              (purchase) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF325183))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 15,
                      child: Text(formatDate(purchase.purchasedAt)),
                    ),
                    Expanded(
                      flex: 22,
                      child: Text(
                        '${purchase.productName} (${purchase.productModel.isEmpty ? '-' : purchase.productModel})',
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Text(
                        '${purchase.quantity.toStringAsFixed(purchase.quantity % 1 == 0 ? 0 : 2)} ${purchase.unit}',
                      ),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(formatMoney(purchase.totalCost)),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(formatMoney(purchase.paidAmount)),
                    ),
                    Expanded(
                      flex: 12,
                      child: Text(
                        formatMoney(purchase.debtAmount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Text(paymentLabel(purchase.paymentType)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierPaymentsTable extends StatelessWidget {
  const _SupplierPaymentsTable({
    required this.payments,
    required this.formatDate,
    required this.formatMoney,
  });

  final List<SupplierPaymentRecord> payments;
  final String Function(DateTime? value) formatDate;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 18, child: Text('Sana')),
                Expanded(flex: 14, child: Text('Summa')),
                Expanded(flex: 24, child: Text('Izoh')),
              ],
            ),
          ),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('To\'lovlar hali yo\'q'),
            )
          else
            ...payments.map(
              (payment) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF325183))),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 18, child: Text(formatDate(payment.paidAt))),
                    Expanded(
                      flex: 14,
                      child: Text(formatMoney(payment.amount)),
                    ),
                    Expanded(
                      flex: 24,
                      child: Text(payment.note.isEmpty ? '-' : payment.note),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SupplierDebtRowsTable extends StatelessWidget {
  const _SupplierDebtRowsTable({
    required this.purchases,
    required this.formatDate,
    required this.formatMoney,
  });

  final List<SupplierPurchaseRecord> purchases;
  final String Function(DateTime? value) formatDate;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF203766),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFF365892),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 18, child: Text('Sana')),
                Expanded(flex: 28, child: Text('Mahsulot')),
                Expanded(flex: 18, child: Text('Jami qarz qoldig\'i')),
              ],
            ),
          ),
          if (purchases.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Qarz yozuvlari yo\'q'),
            )
          else
            ...purchases.map(
              (purchase) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF325183))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 18,
                      child: Text(formatDate(purchase.purchasedAt)),
                    ),
                    Expanded(
                      flex: 28,
                      child: Text(
                        purchase.productModel.isEmpty ||
                                purchase.productModel == '-'
                            ? purchase.productName
                            : '${purchase.productName} (${purchase.productModel})',
                      ),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(
                        formatMoney(purchase.debtAmount),
                        style: const TextStyle(
                          color: Color(0xFFFF5B5B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F3561),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF325183)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
          child,
        ],
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.label,
    required this.width,
    required this.child,
  });

  final String label;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(label), const SizedBox(height: 8), child],
      ),
    );
  }
}

class _ReceiptItemRow extends StatelessWidget {
  const _ReceiptItemRow({
    required this.fields,
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
  });

  final ReceiptFieldsRecord fields;
  final String name;
  final String qty;
  final String price;
  final String total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Expanded(child: Text(qty, textAlign: TextAlign.center)),
          if (fields.showItemUnitPrice)
            Expanded(child: Text(price, textAlign: TextAlign.right)),
          if (fields.showItemLineTotal)
            Expanded(
              child: Text(
                total,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active ? const Color(0xFF4378FF) : const Color(0xFF182847),
        ),
        child: Row(
          children: [Icon(icon), const SizedBox(width: 12), Text(label)],
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent();

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  bool _redirecting = false;

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(dashboardOverviewProvider);
    return overviewAsync.when(
      data: (overview) => Text('Mahsulotlar: ${overview.productsCount}'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        if (_isUnauthorizedError(error)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleUnauthorized();
          });
          return const Center(
            child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
          );
        }
        return Text('Xatolik: $error');
      },
    );
  }
}

class _CategoriesDirectContent extends ConsumerStatefulWidget {
  const _CategoriesDirectContent();

  @override
  ConsumerState<_CategoriesDirectContent> createState() =>
      _CategoriesDirectContentState();
}

class _CategoriesDirectContentState
    extends ConsumerState<_CategoriesDirectContent> {
  late Future<List<CategoryRecord>> _future;
  bool _saving = false;
  String _errorMessage = '';
  bool _redirecting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CategoryRecord>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }
    final repo = ref.read(categoriesRepositoryProvider);
    return repo.fetchCategories(session.token);
  }

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openCategoryDialog({CategoryRecord? category}) async {
    final controller = TextEditingController(text: category?.name ?? '');
    final formKey = GlobalKey<FormState>();
    String localError = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17284B),
              title: Text(
                category == null
                    ? 'Yangi kategoriya qo‘shish'
                    : 'Kategoriyani edit qilish',
              ),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Kategoriya nomi',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Kategoriya nomi kerak'
                            : null,
                      ),
                      if (localError.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          localError,
                          style: const TextStyle(color: Color(0xFFFF8A8A)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Bekor qilish'),
                ),
                ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setState(() {
                            _saving = true;
                            _errorMessage = '';
                          });
                          setLocalState(() {
                            localError = '';
                          });

                          try {
                            final session = ref
                                .read(authControllerProvider)
                                .valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }

                            if (category == null) {
                              await ref
                                  .read(categoriesRepositoryProvider)
                                  .createCategory(
                                    token: session.token,
                                    name: controller.text,
                                  );
                            } else {
                              await ref
                                  .read(categoriesRepositoryProvider)
                                  .updateCategory(
                                    token: session.token,
                                    id: category.id,
                                    name: controller.text,
                                  );
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            final message = error
                                .toString()
                                .replaceFirst('Exception: ', '')
                                .replaceAll(
                                  'DioException [bad response]: ',
                                  '',
                                );
                            setLocalState(() {
                              localError = message;
                            });
                          } finally {
                            if (mounted) {
                              setState(() {
                                _saving = false;
                              });
                            }
                          }
                        },
                  child: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _openCreateDialog() async {
    await _openCategoryDialog();
  }

  Future<void> _openEditDialog(CategoryRecord category) async {
    await _openCategoryDialog(category: category);
  }

  Future<void> _deleteCategory(CategoryRecord category) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Kategoriyani o‘chirish'),
          content: Text('"${category.name}" kategoriyasini o‘chirasizmi?'),
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
              child: const Text('O‘chirish'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;

    try {
      setState(() {
        _saving = true;
        _errorMessage = '';
      });

      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) {
        throw Exception('Session topilmadi');
      }

      await ref
          .read(categoriesRepositoryProvider)
          .deleteCategory(token: session.token, id: category.id);

      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceAll('DioException [bad response]: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CategoryRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (_isUnauthorizedError(snapshot.error!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleUnauthorized();
            });
            return const Center(
              child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
            );
          }
          return Center(child: Text('Xatolik: ${snapshot.error}'));
        }
        final items = snapshot.data ?? const <CategoryRecord>[];
        if (items.isEmpty) {
          return const Center(child: Text('Kategoriya topilmadi'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kategoriyalar ro‘yxati',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 260,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _openCreateDialog,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Kategoriya qo‘shish'),
              ),
            ),
            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty) ...[
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Color(0xFFFF8A8A),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF223A69),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 148,
                          height: 42,
                          child: FilledButton.tonalIcon(
                            onPressed: _saving
                                ? null
                                : () => _openEditDialog(item),
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            label: const Text('Tahrirlash'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          height: 42,
                          child: ElevatedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _deleteCategory(item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.delete_rounded, size: 18),
                            label: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CustomersDirectContent extends ConsumerStatefulWidget {
  const _CustomersDirectContent();

  @override
  ConsumerState<_CustomersDirectContent> createState() =>
      _CustomersDirectContentState();
}

class _CustomersDirectContentState
    extends ConsumerState<_CustomersDirectContent> {
  static const int _pageSize = 14;

  late Future<List<dynamic>> _future;
  bool _saving = false;
  bool _redirecting = false;
  String _errorMessage = '';
  String _search = '';
  int _page = 1;
  final _moneyFormat = NumberFormat.decimalPattern('en_US');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      throw Exception('Session topilmadi');
    }
    return Future.wait<dynamic>([
      ref.read(customersRepositoryProvider).fetchCustomers(session.token),
      ref.read(settingsRepositoryProvider).fetchSettings(session.token),
    ]);
  }

  Future<void> _reload() async {
    setState(() {
      _page = 1;
      _future = _load();
    });
  }

  Future<void> _handleUnauthorized() async {
    if (_redirecting) return;
    _redirecting = true;
    await ref.read(authControllerProvider.notifier).signOut();
  }

  String _formatMoney(double amount, AppSettingsRecord settings) {
    if (settings.displayCurrency == 'usd' && settings.usdRate > 0) {
      return '${(amount / settings.usdRate).toStringAsFixed(2)} \$';
    }
    return '${_moneyFormat.format(amount.round())} so\'m';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd.MM.yyyy, HH:mm').format(value.toLocal());
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      final status = error.response?.statusCode;
      if (status != null) {
        return 'So\'rov xatosi: $status';
      }
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('DioException [bad response]: ', '')
        .replaceAll('DioException [connection error]: ', '');
  }

  double _parseAmount(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
  }

  Future<void> _openCustomerDialog({
    required AppSettingsRecord settings,
    CustomerRecord? customer,
  }) async {
    final fullNameController = TextEditingController(
      text: customer?.fullName ?? '',
    );
    final phoneController = TextEditingController(text: customer?.phone ?? '');
    final addressController = TextEditingController(
      text: customer?.address ?? '',
    );
    final openingBalanceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String currency = settings.displayCurrency;
    String localError = '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17284B),
              title: Text(
                customer == null ? 'Yangi mijoz' : 'Mijozni tahrirlash',
              ),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameController,
                        decoration: const InputDecoration(
                          labelText: 'Ism-familya',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Ism-familya kerak'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Telefon'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Telefon kerak'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: 'Manzil'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Manzil kerak'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: openingBalanceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Astatka qarz',
                          hintText: '0',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: currency,
                        items: const [
                          DropdownMenuItem(value: 'uzs', child: Text('SO\'M')),
                          DropdownMenuItem(value: 'usd', child: Text('USD')),
                        ],
                        decoration: const InputDecoration(labelText: 'Valyuta'),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setLocalState(() {
                                  currency = value == 'usd' ? 'usd' : 'uzs';
                                });
                              },
                      ),
                      if (localError.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          localError,
                          style: const TextStyle(color: Color(0xFFFF8A8A)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Bekor qilish'),
                ),
                ElevatedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          setState(() {
                            _saving = true;
                            _errorMessage = '';
                          });
                          setLocalState(() {
                            localError = '';
                          });

                          try {
                            final session = ref
                                .read(authControllerProvider)
                                .valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }
                            final repo = ref.read(customersRepositoryProvider);
                            final openingBalance = _parseAmount(
                              openingBalanceController.text,
                            );

                            if (customer == null) {
                              await repo.createCustomer(
                                token: session.token,
                                fullName: fullNameController.text,
                                phone: phoneController.text,
                                address: addressController.text,
                                openingBalanceAmount: openingBalance,
                                openingBalanceCurrency: currency,
                              );
                            } else {
                              await repo.updateCustomer(
                                token: session.token,
                                id: customer.id,
                                fullName: fullNameController.text,
                                phone: phoneController.text,
                                address: addressController.text,
                                openingBalanceAmount: openingBalance,
                                openingBalanceCurrency: currency,
                              );
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            setLocalState(() {
                              localError = _friendlyError(error);
                            });
                          } finally {
                            if (mounted) {
                              setState(() {
                                _saving = false;
                              });
                            }
                          }
                        },
                  child: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
                ),
              ],
            );
          },
        );
      },
    );

    fullNameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    openingBalanceController.dispose();
  }

  Future<void> _openLedgerDialog({
    required CustomerRecord customer,
    required AppSettingsRecord settings,
  }) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String paymentError = '';
    bool payLoading = false;
    bool showPaymentHistory = false;

    try {
      if (!mounted) return;

      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) {
        throw Exception('Session topilmadi');
      }

      CustomerLedgerRecord ledger = await ref
          .read(customersRepositoryProvider)
          .fetchLedger(token: session.token, id: customer.id);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setLocalState) {
              final sortedSales = [...ledger.sales]
                ..sort(
                  (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
                    a.createdAt ?? DateTime(2000),
                  ),
                );
              final totalDebt = ledger.totals.totalDebt;
              final totalPaid = ledger.totals.totalPaid;
              final totalDebtAllTime = totalDebt + totalPaid;
              final media = MediaQuery.of(context).size;
              final contentWidth = media.width.clamp(860.0, 1180.0) - 80;
              final contentHeight = media.height.clamp(640.0, 920.0) - 120;

              void setQuickAmount(double ratio) {
                final next =
                    settings.displayCurrency == 'usd' && settings.usdRate > 0
                    ? (totalDebt * ratio) / settings.usdRate
                    : (totalDebt * ratio);
                amountController.text = next % 1 == 0
                    ? next.toInt().toString()
                    : next.toStringAsFixed(2);
              }

              return AlertDialog(
                backgroundColor: const Color(0xFF17284B),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${customer.fullName} - Qarz tarixi',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                content: SizedBox(
                  width: contentWidth,
                  height: contentHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${customer.phone} | ${customer.address}',
                        style: const TextStyle(color: Color(0xFFAEC6EF)),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SummaryCard(
                            label: 'Jami qarz',
                            value: _formatMoney(totalDebtAllTime, settings),
                          ),
                          _SummaryCard(
                            label: 'To\'langan',
                            value: _formatMoney(totalPaid, settings),
                          ),
                          _SummaryCard(
                            label: 'Qolgan qarz',
                            value: _formatMoney(totalDebt, settings),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Form(
                        key: formKey,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [
                            SizedBox(
                              width: 220,
                              child: TextFormField(
                                controller: amountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'To\'lov summasi',
                                ),
                                validator: (value) =>
                                    (_parseAmount(value ?? '') <= 0)
                                    ? 'Summa kiriting'
                                    : null,
                              ),
                            ),
                            SizedBox(
                              width: 320,
                              child: TextFormField(
                                controller: noteController,
                                decoration: const InputDecoration(
                                  labelText: 'Izoh',
                                ),
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: payLoading
                                  ? null
                                  : () => setQuickAmount(0.25),
                              child: const Text('25%'),
                            ),
                            FilledButton.tonal(
                              onPressed: payLoading
                                  ? null
                                  : () => setQuickAmount(0.5),
                              child: const Text('50%'),
                            ),
                            FilledButton.tonal(
                              onPressed: payLoading
                                  ? null
                                  : () => setQuickAmount(1),
                              child: const Text('100%'),
                            ),
                            ElevatedButton(
                              onPressed: payLoading
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate()) {
                                        return;
                                      }
                                      setLocalState(() {
                                        payLoading = true;
                                        paymentError = '';
                                      });
                                      try {
                                        var amount = _parseAmount(
                                          amountController.text,
                                        );
                                        if (settings.displayCurrency == 'usd' &&
                                            settings.usdRate > 0) {
                                          amount *= settings.usdRate;
                                        }
                                        await ref
                                            .read(customersRepositoryProvider)
                                            .payDebt(
                                              token: session.token,
                                              id: customer.id,
                                              amount: amount,
                                              note: noteController.text,
                                            );
                                        ledger = await ref
                                            .read(customersRepositoryProvider)
                                            .fetchLedger(
                                              token: session.token,
                                              id: customer.id,
                                            );
                                        amountController.clear();
                                        noteController.clear();
                                        await _reload();
                                        setLocalState(() {});
                                      } catch (error) {
                                        paymentError = _friendlyError(error);
                                        setLocalState(() {});
                                      } finally {
                                        setLocalState(() {
                                          payLoading = false;
                                        });
                                      }
                                    },
                              child: Text(
                                payLoading ? 'Saqlanmoqda...' : 'Qarz to\'lash',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 14,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Jami savdo: ${_formatMoney(ledger.totals.totalSalesAmount, settings)}',
                          ),
                          Text(
                            'Jami to\'langan: ${_formatMoney(totalPaid, settings)}',
                          ),
                          TextButton(
                            onPressed: () {
                              setLocalState(() {
                                showPaymentHistory = !showPaymentHistory;
                              });
                            },
                            child: Text(
                              showPaymentHistory
                                  ? 'To\'lov tarixini yopish'
                                  : 'To\'lov tarixi',
                            ),
                          ),
                        ],
                      ),
                      if (paymentError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 6),
                          child: Text(
                            paymentError,
                            style: const TextStyle(color: Color(0xFFFF8A8A)),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CustomerLedgerSalesTable(
                                sortedSales: sortedSales,
                                formatDate: _formatDate,
                                formatMoney: (amount) =>
                                    _formatMoney(amount, settings),
                              ),
                              if (showPaymentHistory) ...[
                                const SizedBox(height: 14),
                                const Text(
                                  'To\'lovlar tarixi',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _CustomerLedgerPaymentsTable(
                                  payments: ledger.payments,
                                  formatDate: _formatDate,
                                  formatMoney: (amount) =>
                                      _formatMoney(amount, settings),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                actions: [
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Yopish'),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _deleteCustomer(CustomerRecord customer) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Mijozni o\'chirish'),
          content: Text('"${customer.fullName}" mijozini o\'chirasizmi?'),
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

    try {
      setState(() {
        _saving = true;
        _errorMessage = '';
      });
      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) throw Exception('Session topilmadi');
      await ref
          .read(customersRepositoryProvider)
          .deleteCustomer(token: session.token, id: customer.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (_isUnauthorizedError(snapshot.error!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleUnauthorized();
            });
            return const Center(
              child: Text('Session tugadi. Login sahifaga qaytilmoqda...'),
            );
          }
          return Center(child: Text('Xatolik: ${snapshot.error}'));
        }

        final customersData = snapshot.data![0] as CustomersListRecord;
        final settings = snapshot.data![1] as AppSettingsRecord;
        final query = _search.trim().toLowerCase();
        final visibleCustomers = query.isEmpty
            ? customersData.customers
            : customersData.customers.where((customer) {
                final text = [
                  customer.fullName,
                  customer.phone,
                  customer.address,
                  customer.totalDebt.toString(),
                  customer.totalPaid.toString(),
                ].join(' ').toLowerCase();
                return text.contains(query);
              }).toList();
        final totalPages = visibleCustomers.isEmpty
            ? 1
            : (visibleCustomers.length / _pageSize).ceil();
        final safePage = _page.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, visibleCustomers.length);
        final pagedCustomers = visibleCustomers.sublist(start, end);

        if (safePage != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _page = safePage;
              });
            }
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Clientlar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  height: 44,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Qidirish...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                        _page = 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _openCustomerDialog(settings: settings),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Mijoz qo\'shish'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryCard(
                  label: 'Mijozlar',
                  value: '${customersData.summary.totalCustomers}',
                ),
                _SummaryCard(
                  label: 'Qarzdorlar',
                  value: '${customersData.summary.activeDebtors}',
                ),
                _SummaryCard(
                  label: 'Jami qarz',
                  value: _formatMoney(
                    customersData.summary.totalDebt,
                    settings,
                  ),
                ),
                _SummaryCard(
                  label: 'Jami to\'langan',
                  value: _formatMoney(
                    customersData.summary.totalPaid,
                    settings,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Color(0xFFFF8A8A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: _CustomersTable(
                customers: pagedCustomers,
                safePage: safePage,
                pageSize: _pageSize,
                totalPages: totalPages,
                totalItems: visibleCustomers.length,
                formatMoney: (amount) => _formatMoney(amount, settings),
                onEdit: (customer) =>
                    _openCustomerDialog(settings: settings, customer: customer),
                onOpenLedger: (customer) =>
                    _openLedgerDialog(customer: customer, settings: settings),
                onDelete: (customer) => _deleteCustomer(customer),
                onPrevPage: safePage > 1
                    ? () => setState(() => _page = safePage - 1)
                    : null,
                onNextPage: safePage < totalPages
                    ? () => setState(() => _page = safePage + 1)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}
