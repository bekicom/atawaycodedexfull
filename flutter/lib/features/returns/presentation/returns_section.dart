import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../returns/data/returns_repository.dart';
import '../../returns/domain/returns_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';

class ReturnsDirectContent extends ConsumerStatefulWidget {
  const ReturnsDirectContent({super.key});

  @override
  ConsumerState<ReturnsDirectContent> createState() =>
      _ReturnsDirectContentState();
}

class _ReturnsDirectContentState extends ConsumerState<ReturnsDirectContent> {
  static const int _pageSize = 10;

  late Future<List<dynamic>> _future;
  bool _redirecting = false;
  String _period = 'today';
  String _search = '';
  String _dateFrom = '';
  String _dateTo = '';
  int _page = 1;
  final DateFormat _inputFormat = DateFormat('yyyy-MM-dd');
  final DateFormat _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _dateFrom = _inputFormat.format(today);
    _dateTo = _inputFormat.format(today);
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) throw Exception('Session topilmadi');
    return Future.wait<dynamic>([
      ref.read(returnsRepositoryProvider).fetchReturns(
            token: session.token,
            period: _period,
            from: _dateFrom,
            to: _dateTo,
          ),
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

  bool _isUnauthorizedError(Object error) {
    if (error is DioException) return error.response?.statusCode == 401;
    final text = error.toString().toLowerCase();
    return text.contains('401') || text.contains('unauthorized');
  }

  String _formatNumber(double value) {
    final rounded = (value * 100).round() / 100;
    final hasFraction = (rounded - rounded.truncate()).abs() > 0.0001;
    return NumberFormat.decimalPattern('en_US').format(
      hasFraction ? rounded : rounded.round(),
    );
  }

  String _formatMoney(double amount, AppSettingsRecord settings) {
    if (settings.displayCurrency == 'usd' && settings.usdRate > 0) {
      return '${_formatNumber(amount / settings.usdRate)} \$';
    }
    return '${_formatNumber(amount)} so\'m';
  }

  String _formatQty(double qty) {
    return qty % 1 == 0 ? qty.round().toString() : qty.toStringAsFixed(2);
  }

  String _paymentLabel(String value) {
    final v = value.toLowerCase();
    if (v == 'cash') return 'Naqd';
    if (v == 'card') return 'Karta';
    if (v == 'click') return 'Click';
    if (v == 'mixed') return 'Aralash';
    if (v == 'debt') return 'Qarzga';
    return value.isEmpty ? '-' : value;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = DateTime.tryParse(isFrom ? _dateFrom : _dateTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = _inputFormat.format(picked);
      } else {
        _dateTo = _inputFormat.format(picked);
      }
      _period = 'all';
    });
    await _reload();
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

        final returnsData = snapshot.data![0] as ReturnsRecord;
        final settings = snapshot.data![1] as AppSettingsRecord;
        final query = _search.trim().toLowerCase();
        final filtered = query.isEmpty
            ? returnsData.returns
            : returnsData.returns.where((ret) {
                final text = [
                  ret.cashierUsername,
                  ret.paymentType,
                  ret.note,
                  ...ret.items.map((item) => item.productName),
                ].join(' ').toLowerCase();
                return text.contains(query);
              }).toList();

        final totalPages =
            filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
        final safePage = _page.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, filtered.length);
        final pageItems = filtered.sublist(start, end);

        if (safePage != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _page = safePage);
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Qaytarib olish',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PeriodButton(
                      label: '1 kunlik',
                      active: _period == 'today',
                      onTap: () async {
                        setState(() => _period = 'today');
                        await _reload();
                      },
                    ),
                    _PeriodButton(
                      label: 'Kecha',
                      active: _period == 'yesterday',
                      onTap: () async {
                        setState(() => _period = 'yesterday');
                        await _reload();
                      },
                    ),
                    _PeriodButton(
                      label: '7 kun',
                      active: _period == '7d',
                      onTap: () async {
                        setState(() => _period = '7d');
                        await _reload();
                      },
                    ),
                    _PeriodButton(
                      label: '30 kun',
                      active: _period == '30d',
                      onTap: () async {
                        setState(() => _period = '30d');
                        await _reload();
                      },
                    ),
                    _PeriodButton(
                      label: 'Hammasi',
                      active: _period == 'all',
                      onTap: () async {
                        setState(() => _period = 'all');
                        await _reload();
                      },
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 220,
                  height: 46,
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
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _DateFilterChip(
                  label: 'Dan',
                  value: _dateFrom,
                  onTap: () => _pickDate(isFrom: true),
                ),
                const SizedBox(width: 10),
                _DateFilterChip(
                  label: 'Gacha',
                  value: _dateTo,
                  onTap: () => _pickDate(isFrom: false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ReturnSummaryCard(
                  label: 'Vozvratlar',
                  value: '${returnsData.summary.totalReturns}',
                ),
                _ReturnSummaryCard(
                  label: 'Jami qaytgan',
                  value: _formatMoney(
                    returnsData.summary.totalReturnedAmount,
                    settings,
                  ),
                ),
                _ReturnSummaryCard(
                  label: 'Naqd qaytgan',
                  value: _formatMoney(
                    returnsData.summary.totalReturnedCash,
                    settings,
                  ),
                ),
                _ReturnSummaryCard(
                  label: 'Karta qaytgan',
                  value: _formatMoney(
                    returnsData.summary.totalReturnedCard,
                    settings,
                  ),
                ),
                _ReturnSummaryCard(
                  label: 'Click / Miqdor',
                  value:
                      '${_formatMoney(returnsData.summary.totalReturnedClick, settings)} / ${_formatQty(returnsData.summary.totalReturnedQty)}',
                  wide: true,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth > 1750
                          ? constraints.maxWidth
                          : 1750,
                      height: constraints.maxHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF223D72),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF345891)),
                        ),
                        child: Column(
                          children: [
                            const _ReturnsHeaderRow(),
                            Expanded(
                              child: pageItems.isEmpty
                                  ? const Center(child: Text('Vozvratlar topilmadi'))
                                  : ListView.separated(
                                      itemCount: pageItems.length,
                                      separatorBuilder: (context, index) => const Divider(
                                        height: 1,
                                        color: Color(0xFF2F4B7F),
                                      ),
                                      itemBuilder: (context, index) {
                                        final ret = pageItems[index];
                                        final names = ret.items
                                            .map((item) => item.productName)
                                            .join(', ');
                                        final qty = ret.items
                                            .map((item) => '${_formatQty(item.quantity)} ${item.unit}')
                                            .join(', ');
                                        return _ReturnsDataRow(
                                          dark: index.isEven,
                                          returnCreatedAt:
                                              ret.returnCreatedAt == null
                                                  ? '-'
                                                  : _dateTimeFormat.format(
                                                      ret.returnCreatedAt!,
                                                    ),
                                          saleCreatedAt: ret.saleCreatedAt == null
                                              ? '-'
                                              : _dateTimeFormat.format(
                                                  ret.saleCreatedAt!,
                                                ),
                                          cashier: ret.cashierUsername,
                                          items: names,
                                          qty: qty,
                                          paymentType:
                                              _paymentLabel(ret.paymentType),
                                          cash: _formatMoney(
                                            ret.payments.cash,
                                            settings,
                                          ),
                                          card: _formatMoney(
                                            ret.payments.card,
                                            settings,
                                          ),
                                          click: _formatMoney(
                                            ret.payments.click,
                                            settings,
                                          ),
                                          total: _formatMoney(
                                            ret.totalAmount,
                                            settings,
                                          ),
                                          note: ret.note.isEmpty ? '-' : ret.note,
                                        );
                                      },
                                    ),
                            ),
                            _ReturnsPagination(
                              safePage: safePage,
                              totalPages: totalPages,
                              onPrev: safePage > 1
                                  ? () => setState(() => _page = safePage - 1)
                                  : null,
                              onNext: safePage < totalPages
                                  ? () => setState(() => _page = safePage + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ),
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

class _PeriodButton extends StatelessWidget {
  const _PeriodButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor:
              active ? const Color(0xFF2B6BFF) : const Color(0xFF203863),
          foregroundColor: Colors.white,
        ),
        child: Text(label),
      ),
    );
  }
}

class _DateFilterChip extends StatelessWidget {
  const _DateFilterChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF203863),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF345891)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: $value'),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_month_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ReturnSummaryCard extends StatelessWidget {
  const _ReturnSummaryCard({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide ? 260 : 190,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A467B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF375A95)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFFC8D3EF))),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ReturnsHeaderRow extends StatelessWidget {
  const _ReturnsHeaderRow();

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
          _ReturnHeaderCell(flex: 16, text: 'Vaqt'),
          _ReturnHeaderCell(flex: 16, text: 'Sotuv vaqti'),
          _ReturnHeaderCell(flex: 14, text: 'Kassir'),
          _ReturnHeaderCell(flex: 26, text: 'Mahsulotlar'),
          _ReturnHeaderCell(flex: 18, text: 'Soni'),
          _ReturnHeaderCell(flex: 12, text: 'To\'lov'),
          _ReturnHeaderCell(flex: 12, text: 'Naqd'),
          _ReturnHeaderCell(flex: 12, text: 'Karta'),
          _ReturnHeaderCell(flex: 12, text: 'Click'),
          _ReturnHeaderCell(flex: 14, text: 'Qaytgan summa'),
          _ReturnHeaderCell(flex: 18, text: 'Izoh'),
        ],
      ),
    );
  }
}

class _ReturnHeaderCell extends StatelessWidget {
  const _ReturnHeaderCell({
    required this.flex,
    required this.text,
  });

  final int flex;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ReturnsDataRow extends StatelessWidget {
  const _ReturnsDataRow({
    required this.dark,
    required this.returnCreatedAt,
    required this.saleCreatedAt,
    required this.cashier,
    required this.items,
    required this.qty,
    required this.paymentType,
    required this.cash,
    required this.card,
    required this.click,
    required this.total,
    required this.note,
  });

  final bool dark;
  final String returnCreatedAt;
  final String saleCreatedAt;
  final String cashier;
  final String items;
  final String qty;
  final String paymentType;
  final String cash;
  final String card;
  final String click;
  final String total;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: dark ? const Color(0xFF203863) : const Color(0xFF1C325B),
      child: Row(
        children: [
          _ReturnDataCell(flex: 16, text: returnCreatedAt),
          _ReturnDataCell(flex: 16, text: saleCreatedAt),
          _ReturnDataCell(flex: 14, text: cashier),
          _ReturnDataCell(flex: 26, text: items),
          _ReturnDataCell(flex: 18, text: qty),
          _ReturnDataCell(flex: 12, text: paymentType),
          _ReturnDataCell(flex: 12, text: cash),
          _ReturnDataCell(flex: 12, text: card),
          _ReturnDataCell(flex: 12, text: click),
          _ReturnDataCell(flex: 14, text: total),
          _ReturnDataCell(flex: 18, text: note),
        ],
      ),
    );
  }
}

class _ReturnDataCell extends StatelessWidget {
  const _ReturnDataCell({
    required this.flex,
    required this.text,
  });

  final int flex;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _ReturnsPagination extends StatelessWidget {
  const _ReturnsPagination({
    required this.safePage,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  final int safePage;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A2E57),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: 44,
            height: 40,
            child: FilledButton.tonal(
              onPressed: onPrev,
              child: const Text('<'),
            ),
          ),
          const SizedBox(width: 12),
          Text('$safePage / $totalPages'),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            height: 40,
            child: FilledButton.tonal(
              onPressed: onNext,
              child: const Text('>'),
            ),
          ),
        ],
      ),
    );
  }
}
