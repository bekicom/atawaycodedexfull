import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/dashboard_overview.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../expenses/domain/expense_record.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product_record.dart';
import '../../returns/data/returns_repository.dart';
import '../../returns/domain/returns_record.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sales_history_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier_record.dart';

class HomeDashboardSection extends ConsumerStatefulWidget {
  const HomeDashboardSection({super.key});

  @override
  ConsumerState<HomeDashboardSection> createState() =>
      _HomeDashboardSectionState();
}

class _HomeDashboardSectionState extends ConsumerState<HomeDashboardSection> {
  bool _redirecting = false;
  String _search = '';
  late String _dateFrom;
  late String _dateTo;
  late Future<_HomeBundle> _future;
  final DateFormat _dateInput = DateFormat('yyyy-MM-dd');
  final DateFormat _dateLabel = DateFormat('dd.MM.yyyy');
  final DateFormat _timeLabel = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateFrom = _dateInput.format(now);
    _dateTo = _dateInput.format(now);
    _future = _load();
  }

  Future<_HomeBundle> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) throw Exception('Session topilmadi');

    final results = await Future.wait<dynamic>([
      ref.read(dashboardRepositoryProvider).fetchOverview(session.token),
      ref.read(productsRepositoryProvider).fetchProducts(token: session.token),
      ref.read(suppliersRepositoryProvider).fetchSuppliers(session.token),
      ref.read(expensesRepositoryProvider).fetchExpenses(session.token),
      ref
          .read(salesRepositoryProvider)
          .fetchSales(
            token: session.token,
            period: 'all',
            from: _dateFrom,
            to: _dateTo,
          ),
      ref
          .read(returnsRepositoryProvider)
          .fetchReturns(
            token: session.token,
            period: 'all',
            from: _dateFrom,
            to: _dateTo,
          ),
      ref.read(settingsRepositoryProvider).fetchSettings(session.token),
    ]);

    return _HomeBundle(
      overview: results[0] as DashboardOverview,
      products: results[1] as List<ProductRecord>,
      suppliers: results[2] as List<SupplierRecord>,
      expenses: results[3] as List<ExpenseRecord>,
      sales: results[4] as SalesHistoryRecord,
      returns: results[5] as ReturnsRecord,
      settings: results[6] as AppSettingsRecord,
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

  bool _isUnauthorizedError(Object error) {
    if (error is DioException) return error.response?.statusCode == 401;
    final text = error.toString().toLowerCase();
    return text.contains('401') || text.contains('unauthorized');
  }

  String _formatNumber(double value) {
    final rounded = (value * 100).round() / 100;
    final hasFraction = (rounded - rounded.truncate()).abs() > 0.0001;
    return NumberFormat.decimalPattern(
      'en_US',
    ).format(hasFraction ? rounded : rounded.round());
  }

  String _formatMoney(double amount, AppSettingsRecord settings) {
    if (settings.displayCurrency == 'usd' && settings.usdRate > 0) {
      return '${_formatNumber(amount / settings.usdRate)} \$';
    }
    return '${_formatNumber(amount)} so\'m';
  }

  bool _inRange(DateTime? value) {
    if (value == null) return true;
    final from = DateTime.tryParse(_dateFrom);
    final to = DateTime.tryParse(_dateTo);
    if (from != null &&
        value.isBefore(DateTime(from.year, from.month, from.day))) {
      return false;
    }
    if (to != null) {
      final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
      if (value.isAfter(end)) return false;
    }
    return true;
  }

  String _paymentLabel(String value) {
    final v = value.toLowerCase();
    if (v == 'cash') return 'Naqd';
    if (v == 'card') return 'Karta';
    if (v == 'click') return 'Click';
    if (v == 'mixed') return 'Aralash';
    if (v == 'debt') return 'Qarzga';
    if (v == 'debt_payment') return 'Qarzdor to\'lovi';
    if (v == 'naqd') return 'Naqd';
    if (v == 'qarz') return 'Qarzga';
    return value.isEmpty ? '-' : value;
  }

  void _setPreset(int days) {
    final to = DateTime.now();
    final from = to.subtract(Duration(days: days - 1));
    setState(() {
      _dateFrom = _dateInput.format(from);
      _dateTo = _dateInput.format(to);
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeBundle>(
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
        final filteredExpenses = data.expenses
            .where((item) => _inRange(item.spentAt))
            .toList();

        final totalStockQty = data.products.fold<double>(
          0,
          (sum, item) => sum + item.quantity,
        );
        final stockCostValue = data.products.fold<double>(
          0,
          (sum, item) => sum + (item.quantity * item.purchasePrice),
        );
        final stockRetailValue = data.products.fold<double>(
          0,
          (sum, item) => sum + (item.quantity * item.retailPrice),
        );
        final totalDebt = data.suppliers.fold<double>(
          0,
          (sum, item) => sum + item.stats.totalDebt,
        );
        final expenseTotal = filteredExpenses.fold<double>(
          0,
          (sum, item) => sum + item.amount,
        );
        final cardSales = data.sales.summary.totalCard;
        final cardExpense = (expenseTotal * 0.35).roundToDouble();

        final lowStockProducts = [...data.products]
          ..sort((a, b) => a.quantity.compareTo(b.quantity));
        final visibleLowStock = lowStockProducts.take(8).toList();

        final topDebtors = [...data.suppliers]
          ..sort((a, b) => b.stats.totalDebt.compareTo(a.stats.totalDebt));
        final visibleDebtors = topDebtors.take(5).toList();

        final soldByCategoryMap = <String, double>{};
        for (final sale in data.sales.sales) {
          for (final item in sale.items) {
            final qty = item.quantity - item.returnedQuantity;
            soldByCategoryMap[item.productName] =
                (soldByCategoryMap[item.productName] ?? 0) +
                (qty < 0 ? 0 : qty);
          }
        }
        final soldByCategory =
            soldByCategoryMap.entries
                .map((entry) => _SoldBar(entry.key, entry.value))
                .toList()
              ..sort((a, b) => b.qty.compareTo(a.qty));
        final maxBar = soldByCategory.isEmpty ? 1 : soldByCategory.first.qty;
        final visibleBars = soldByCategory.take(6).toList();

        final recentEvents =
            <_RecentEvent>[
              ...data.sales.sales.map(
                (sale) => _RecentEvent(
                  type: 'Savdo',
                  date: sale.createdAt,
                  products: sale.items
                      .map((item) => item.productName)
                      .join(', '),
                  payment: _paymentLabel(sale.paymentType),
                  amount: sale.totalAmount,
                ),
              ),
              ...data.returns.returns.map(
                (ret) => _RecentEvent(
                  type: 'Vozvrat',
                  date: ret.returnCreatedAt,
                  products: ret.items
                      .map((item) => item.productName)
                      .join(', '),
                  payment: _paymentLabel(ret.paymentType),
                  amount: ret.totalAmount,
                ),
              ),
              ...filteredExpenses.map(
                (expense) => _RecentEvent(
                  type: 'Xarajat',
                  date: expense.spentAt,
                  products: expense.reason,
                  payment: '-',
                  amount: expense.amount,
                ),
              ),
            ]..sort(
              (a, b) => (b.date ?? DateTime(2000)).compareTo(
                a.date ?? DateTime(2000),
              ),
            );

        final q = _search.trim().toLowerCase();
        final visibleEvents =
            (q.isEmpty
                    ? recentEvents
                    : recentEvents.where((event) {
                        final text = [
                          event.type,
                          event.products,
                          event.payment,
                          _formatNumber(event.amount),
                        ].join(' ').toLowerCase();
                        return text.contains(q);
                      }))
                .take(8)
                .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HomeTopBar(
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              onSearch: (value) => setState(() => _search = value),
              onDateFrom: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_dateFrom) ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _dateFrom = _dateInput.format(picked));
                  await _reload();
                }
              },
              onDateTo: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_dateTo) ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _dateTo = _dateInput.format(picked));
                  await _reload();
                }
              },
              onPresetToday: () => _setPreset(1),
              onPreset7: () => _setPreset(7),
              onPreset30: () => _setPreset(30),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _KpiCard(
                            title: 'Tushum',
                            value: _formatMoney(
                              data.sales.summary.totalRevenue,
                              settings,
                            ),
                            subtitle: 'Umumiy tushum',
                            colors: const [
                              Color(0xFF2B65D9),
                              Color(0xFF2FA8E7),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiCard(
                            title: 'Chiqim',
                            value: _formatMoney(expenseTotal, settings),
                            subtitle: 'Hammasi chiqim',
                            colors: const [
                              Color(0xFF16996A),
                              Color(0xFF38B873),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiCard(
                            title: 'Foyda',
                            value: _formatMoney(
                              data.sales.summary.totalProfit,
                              settings,
                            ),
                            subtitle: 'Jami foyda',
                            colors: const [
                              Color(0xFFF08B18),
                              Color(0xFFF5B52F),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiCard(
                            title: 'Karta',
                            value: _formatMoney(cardSales, settings),
                            subtitle: 'Karta orqali tushum',
                            colors: const [
                              Color(0xFFF0A21F),
                              Color(0xFFF6C238),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _KpiCard(
                            title: 'Karta orqali chiqim',
                            value: _formatMoney(cardExpense, settings),
                            subtitle: 'Karta orqali chiqim',
                            colors: const [
                              Color(0xFF3560DA),
                              Color(0xFF447DF7),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 26,
                          child: _InfoPanel(
                            title: 'Ombor Hisobi',
                            bigValue: _formatMoney(stockRetailValue, settings),
                            hint:
                                '${_formatNumber(totalStockQty)} dona mahsulotlar qoldi',
                            child: visibleLowStock.isEmpty
                                ? const _MutedText('Kam qoldiq yo\'q')
                                : ListView(
                                    shrinkWrap: true,
                                    children: visibleLowStock
                                        .map(
                                          (item) => _SimpleRow(
                                            left: item.name,
                                            right:
                                                '${_formatNumber(item.quantity)} ${item.unit}',
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 40,
                          child: _InfoPanel(
                            title: 'Qarzdorlik',
                            topStats: [
                              _PanelTopStat(
                                label: 'Umumiy',
                                value: _formatMoney(totalDebt, settings),
                              ),
                              _PanelTopStat(
                                label: 'To\'lanmagan',
                                value: _formatMoney(totalDebt, settings),
                              ),
                            ],
                            child: visibleDebtors.isEmpty
                                ? const _MutedText('Qarz yo\'q')
                                : ListView(
                                    shrinkWrap: true,
                                    children: visibleDebtors
                                        .map(
                                          (item) => _SimpleRow(
                                            left: item.name,
                                            right: _formatMoney(
                                              item.stats.totalDebt,
                                              settings,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 34,
                          child: _InfoPanel(
                            title: 'Eng ko\'p sotilgan kategoriyalar',
                            child: visibleBars.isEmpty
                                ? const _MutedText('Sotuv yo\'q')
                                : ListView(
                                    shrinkWrap: true,
                                    children: visibleBars
                                        .map(
                                          (bar) => _BarRow(
                                            label: bar.name,
                                            qty: _formatNumber(bar.qty),
                                            percent: maxBar == 0
                                                ? 0
                                                : (bar.qty / maxBar).clamp(
                                                    0,
                                                    1,
                                                  ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _RecentPanel(
                      events: visibleEvents,
                      formatDate: (value) =>
                          value == null ? '-' : _dateLabel.format(value),
                      formatTime: (value) =>
                          value == null ? '-' : _timeLabel.format(value),
                      formatMoney: (amount) => _formatMoney(amount, settings),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _FooterCard(
                            title: 'Skladda: ${_formatNumber(totalStockQty)}',
                            value: 'dona mahsulot',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FooterCard(
                            title: 'Mahsulotlar soni',
                            value: '${data.overview.productsCount}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FooterCard(
                            title: 'Vozvratlar soni',
                            value: '${data.returns.summary.totalReturns}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FooterCard(
                            title: 'Ombor tannarxi',
                            value: _formatMoney(stockCostValue, settings),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _FooterCard(
                            title: 'Ombor sotuv qiymati',
                            value: _formatMoney(stockRetailValue, settings),
                          ),
                        ),
                      ],
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

class _HomeBundle {
  const _HomeBundle({
    required this.overview,
    required this.products,
    required this.suppliers,
    required this.expenses,
    required this.sales,
    required this.returns,
    required this.settings,
  });

  final DashboardOverview overview;
  final List<ProductRecord> products;
  final List<SupplierRecord> suppliers;
  final List<ExpenseRecord> expenses;
  final SalesHistoryRecord sales;
  final ReturnsRecord returns;
  final AppSettingsRecord settings;
}

class _RecentEvent {
  const _RecentEvent({
    required this.type,
    required this.date,
    required this.products,
    required this.payment,
    required this.amount,
  });

  final String type;
  final DateTime? date;
  final String products;
  final String payment;
  final double amount;
}

class _SoldBar {
  const _SoldBar(this.name, this.qty);

  final String name;
  final double qty;
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.dateFrom,
    required this.dateTo,
    required this.onSearch,
    required this.onDateFrom,
    required this.onDateTo,
    required this.onPresetToday,
    required this.onPreset7,
    required this.onPreset30,
  });

  final String dateFrom;
  final String dateTo;
  final ValueChanged<String> onSearch;
  final VoidCallback onDateFrom;
  final VoidCallback onDateTo;
  final VoidCallback onPresetToday;
  final VoidCallback onPreset7;
  final VoidCallback onPreset30;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E57),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2F4B7F)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Asosiy Dashboard',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Bosh sahifa: Umumiy sotuvlar, saqlash holati va keyingi harakatlar.',
                    style: TextStyle(color: Color(0xFFC9D5F2)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * 0.46,
                minWidth: 380,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 42,
                    child: TextField(
                      onChanged: onSearch,
                      decoration: const InputDecoration(
                        hintText: 'Qidirish...',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DateButton(value: dateFrom, onTap: onDateFrom),
                      _DateButton(value: dateTo, onTap: onDateTo),
                      _PresetButton(label: 'Bugun', onTap: onPresetToday),
                      _PresetButton(label: 'O\'tgan 7 kun', onTap: onPreset7),
                      _PresetButton(label: 'O\'tgan 30 kun', onTap: onPreset30),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF13254A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2F4B7F)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value),
            const SizedBox(width: 6),
            const Icon(Icons.calendar_today_outlined, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: FilledButton.tonal(onPressed: onTap, child: Text(label)),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.colors,
  });

  final String title;
  final String value;
  final String subtitle;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 122,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFFDDE8FF))),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(subtitle),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    this.bigValue,
    this.hint,
    this.topStats = const [],
    required this.child,
  });

  final String title;
  final String? bigValue;
  final String? hint;
  final List<_PanelTopStat> topStats;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 360, maxHeight: 420),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E57),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2F4B7F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          if (bigValue != null) ...[
            const SizedBox(height: 10),
            Text(
              bigValue!,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint!, style: const TextStyle(color: Color(0xFFC9D5F2))),
          ],
          if (topStats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: topStats
                  .map(
                    (item) => Expanded(
                      child: Text(
                        '${item.label}: ${item.value}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PanelTopStat {
  const _PanelTopStat({required this.label, required this.value});

  final String label;
  final String value;
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow({required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF203863),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2F4B7F)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(left, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(right, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.qty,
    required this.percent,
  });

  final String label;
  final String qty;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(qty, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: const Color(0xFF29426D),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF2ED35E)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPanel extends StatelessWidget {
  const _RecentPanel({
    required this.events,
    required this.formatDate,
    required this.formatTime,
    required this.formatMoney,
  });

  final List<_RecentEvent> events;
  final String Function(DateTime? value) formatDate;
  final String Function(DateTime? value) formatTime;
  final String Function(double amount) formatMoney;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E57),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2F4B7F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Oxirgi Jarayonlar',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF3A5D98),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Expanded(flex: 12, child: _RecentHeaderCell('Sana')),
                Expanded(flex: 12, child: _RecentHeaderCell('Kategoriya')),
                Expanded(flex: 52, child: _RecentHeaderCell('Mahsulotlar')),
                Expanded(flex: 12, child: _RecentHeaderCell('To\'lov')),
                Expanded(flex: 12, child: _RecentHeaderCell('Summa')),
                Expanded(flex: 8, child: _RecentHeaderCell('Vaqt')),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Jarayon topilmadi'),
            )
          else
            ...events.map(
              (event) => Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF2F4B7F))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 12,
                      child: _RecentCell(formatDate(event.date)),
                    ),
                    Expanded(
                      flex: 12,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2959C7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(event.type),
                        ),
                      ),
                    ),
                    Expanded(flex: 52, child: _RecentCell(event.products)),
                    Expanded(flex: 12, child: _RecentCell(event.payment)),
                    Expanded(
                      flex: 12,
                      child: _RecentCell(formatMoney(event.amount)),
                    ),
                    Expanded(
                      flex: 8,
                      child: _RecentCell(formatTime(event.date)),
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

class _RecentHeaderCell extends StatelessWidget {
  const _RecentHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    );
  }
}

class _RecentCell extends StatelessWidget {
  const _RecentCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

class _FooterCard extends StatelessWidget {
  const _FooterCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E57),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2F4B7F)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: Color(0xFFC9D5F2)));
  }
}
