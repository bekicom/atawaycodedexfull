import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../expenses/data/expenses_repository.dart';
import '../../expenses/domain/expense_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';

class ExpensesDirectContent extends ConsumerStatefulWidget {
  const ExpensesDirectContent({super.key});

  @override
  ConsumerState<ExpensesDirectContent> createState() =>
      _ExpensesDirectContentState();
}

class _ExpensesDirectContentState extends ConsumerState<ExpensesDirectContent> {
  static const int _pageSize = 15;

  late Future<List<dynamic>> _future;
  bool _saving = false;
  bool _redirecting = false;
  String _search = '';
  String _errorMessage = '';
  int _page = 1;
  final DateFormat _dateFormat = DateFormat('dd.MM.yyyy');
  final DateFormat _inputFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) throw Exception('Session topilmadi');
    return Future.wait<dynamic>([
      ref.read(expensesRepositoryProvider).fetchExpenses(session.token),
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

  String _normalizeError(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll('DioException [bad response]: ', '')
        .replaceAll('DioException [connection error]: ', '');
  }

  double _parseDouble(String value) {
    return double.tryParse(value.replaceAll(',', '.').trim()) ?? 0;
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

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<void> _exportExpensesExcel({
    required List<ExpenseRecord> filtered,
    required List<ExpenseRecord> allExpenses,
    required AppSettingsRecord settings,
  }) async {
    final saveLocation = await getSaveLocation(
      suggestedName:
          'xarajatlar_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xls',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xls']),
      ],
    );
    if (saveLocation == null) return;

    final totalFiltered = filtered.fold<double>(0, (sum, item) => sum + item.amount);
    final totalAll = allExpenses.fold<double>(0, (sum, item) => sum + item.amount);

    final rows = filtered
        .map(
          (expense) => '''
            <tr>
              <td>${_escapeHtml(_dateFormat.format(expense.spentAt))}</td>
              <td>${_escapeHtml(_formatMoney(expense.amount, settings))}</td>
              <td>${_escapeHtml(expense.reason.isEmpty ? '-' : expense.reason)}</td>
            </tr>
          ''',
        )
        .join();

    final html = '''
      <html>
      <head>
        <meta charset="utf-8" />
        <style>
          body { font-family: Arial, sans-serif; padding: 18px; color: #111827; }
          h1 { margin: 0 0 8px 0; font-size: 22px; }
          .meta { margin-bottom: 16px; color: #374151; font-size: 13px; }
          .summary { margin-bottom: 16px; border-collapse: collapse; }
          .summary td { border: 1px solid #d1d5db; padding: 8px 10px; }
          .summary .label { background: #e5eefc; font-weight: 700; }
          table { width: 100%; border-collapse: collapse; }
          th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; }
          th { background: #e5eefc; font-weight: 700; }
        </style>
      </head>
      <body>
        <h1>Xarajatlar hisobotі</h1>
        <div class="meta">
          Export vaqti: ${_escapeHtml(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()))}<br/>
          Filtr: ${_escapeHtml(_search.isEmpty ? 'Hammasi' : _search)}
        </div>
        <table class="summary">
          <tr>
            <td class="label">Jami xarajatlar soni</td><td>${allExpenses.length}</td>
            <td class="label">Filtrlangan</td><td>${filtered.length}</td>
            <td class="label">Filtrlangan jami</td><td>${_escapeHtml(_formatMoney(totalFiltered, settings))}</td>
            <td class="label">Barcha jami</td><td>${_escapeHtml(_formatMoney(totalAll, settings))}</td>
          </tr>
        </table>
        <table>
          <thead>
            <tr>
              <th>Sana</th>
              <th>Summa</th>
              <th>Sababi</th>
            </tr>
          </thead>
          <tbody>
            ${rows.isEmpty ? '<tr><td colspan="3">Xarajat topilmadi</td></tr>' : rows}
          </tbody>
        </table>
      </body>
      </html>
    ''';

    final bytes = Uint8List.fromList(html.codeUnits);
    await File(saveLocation.path).writeAsBytes(bytes, flush: true);
  }

  Future<void> _openExpenseDialog({
    required AppSettingsRecord settings,
    ExpenseRecord? expense,
  }) async {
    final amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.toStringAsFixed(0),
    );
    final reasonController = TextEditingController(text: expense?.reason ?? '');
    final dateController = TextEditingController(
      text: _inputFormat.format(expense?.spentAt ?? DateTime.now()),
    );
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
              title: Text(expense == null ? 'Yangi xarajat' : 'Xarajatni edit'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Xarajat summasi'),
                        validator: (value) => _parseDouble(value ?? '') <= 0
                            ? 'Xarajat summasi 0 dan katta bo\'lsin'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: reasonController,
                        decoration: const InputDecoration(labelText: 'Sababi'),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'Sababni kiriting'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: dateController,
                        decoration: const InputDecoration(labelText: 'Sana'),
                        readOnly: true,
                        onTap: () async {
                          final initialDate =
                              DateTime.tryParse(dateController.text) ?? DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            dateController.text = _inputFormat.format(picked);
                          }
                        },
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Ko\'rinishi: ${_formatMoney(_parseDouble(amountController.text), settings)}',
                        ),
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
                          setLocalState(() => localError = '');
                          try {
                            final session =
                                ref.read(authControllerProvider).valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }
                            final repo = ref.read(expensesRepositoryProvider);
                            if (expense == null) {
                              await repo.createExpense(
                                token: session.token,
                                amount: _parseDouble(amountController.text),
                                reason: reasonController.text,
                                spentAt: dateController.text,
                              );
                            } else {
                              await repo.updateExpense(
                                token: session.token,
                                id: expense.id,
                                amount: _parseDouble(amountController.text),
                                reason: reasonController.text,
                                spentAt: dateController.text,
                              );
                            }
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            setLocalState(() => localError = _normalizeError(error));
                          } finally {
                            if (mounted) setState(() => _saving = false);
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

    amountController.dispose();
    reasonController.dispose();
    dateController.dispose();
  }

  Future<void> _deleteExpense(ExpenseRecord expense) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Xarajatni o\'chirish'),
          content: Text('"${expense.reason}" xarajatini o\'chirasizmi?'),
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
      await ref.read(expensesRepositoryProvider).deleteExpense(
            token: session.token,
            id: expense.id,
          );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _normalizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
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

        final expenses = snapshot.data![0] as List<ExpenseRecord>;
        final settings = snapshot.data![1] as AppSettingsRecord;
        final query = _search.trim().toLowerCase();
        final filtered = query.isEmpty
            ? expenses
            : expenses.where((expense) {
                final text = [
                  expense.reason,
                  _dateFormat.format(expense.spentAt),
                  expense.amount.toString(),
                ].join(' ').toLowerCase();
                return text.contains(query);
              }).toList();

        final totalPages =
            filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
        final safePage = _page.clamp(1, totalPages);
        final start = (safePage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, filtered.length);
        final pageItems = filtered.sublist(start, end);
        final totalExpense = filtered.fold<double>(
          0,
          (sum, item) => sum + item.amount,
        );

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
                  'Xarajatlar',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                SizedBox(
                  width: 240,
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
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _openExpenseDialog(settings: settings),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Xarajat qo\'shish'),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _exportExpensesExcel(
                              filtered: filtered,
                              allExpenses: expenses,
                              settings: settings,
                            ),
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
                _ExpenseSummaryCard(label: 'Xarajatlar soni', value: '${expenses.length}'),
                _ExpenseSummaryCard(label: 'Filtrlangan', value: '${filtered.length}'),
                _ExpenseSummaryCard(
                  label: 'Jami xarajat',
                  value: _formatMoney(totalExpense, settings),
                  wide: true,
                ),
              ],
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                style: const TextStyle(
                  color: Color(0xFFFF8A8A),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF223D72),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF345891)),
                ),
                child: Column(
                  children: [
                    const _ExpensesHeaderRow(),
                    Expanded(
                      child: pageItems.isEmpty
                          ? const Center(child: Text('Xarajat topilmadi'))
                          : ListView.separated(
                              itemCount: pageItems.length,
                              separatorBuilder: (context, index) => const Divider(
                                height: 1,
                                color: Color(0xFF2F4B7F),
                              ),
                              itemBuilder: (context, index) {
                                final expense = pageItems[index];
                                return _ExpensesDataRow(
                                  expense: expense,
                                  dateLabel: _dateFormat.format(expense.spentAt),
                                  amountLabel: _formatMoney(expense.amount, settings),
                                  onEdit: () => _openExpenseDialog(
                                    settings: settings,
                                    expense: expense,
                                  ),
                                  onDelete: () => _deleteExpense(expense),
                                  dark: index.isEven,
                                );
                              },
                            ),
                    ),
                    _ExpensesPagination(
                      totalItems: filtered.length,
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
          ],
        );
      },
    );
  }
}

class _ExpenseSummaryCard extends StatelessWidget {
  const _ExpenseSummaryCard({
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
      width: wide ? 280 : 170,
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

class _ExpensesHeaderRow extends StatelessWidget {
  const _ExpensesHeaderRow();

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
          Expanded(flex: 16, child: _ExpenseHeaderText('Sana')),
          Expanded(flex: 16, child: _ExpenseHeaderText('Summa')),
          Expanded(flex: 44, child: _ExpenseHeaderText('Sababi')),
          Expanded(flex: 24, child: _ExpenseHeaderText('Amallar')),
        ],
      ),
    );
  }
}

class _ExpenseHeaderText extends StatelessWidget {
  const _ExpenseHeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
    );
  }
}

class _ExpensesDataRow extends StatelessWidget {
  const _ExpensesDataRow({
    required this.expense,
    required this.dateLabel,
    required this.amountLabel,
    required this.onEdit,
    required this.onDelete,
    required this.dark,
  });

  final ExpenseRecord expense;
  final String dateLabel;
  final String amountLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: dark ? const Color(0xFF203863) : const Color(0xFF1C325B),
      child: Row(
        children: [
          Expanded(flex: 16, child: _ExpenseCell(dateLabel)),
          Expanded(
            flex: 16,
            child: _ExpenseCell(
              amountLabel,
              color: const Color(0xFFFF6B6B),
              weight: FontWeight.w800,
            ),
          ),
          Expanded(flex: 44, child: _ExpenseCell(expense.reason)),
          Expanded(
            flex: 24,
            child: Row(
              children: [
                _ExpenseActionButton(
                  width: 72,
                  label: 'edit',
                  icon: Icons.edit_outlined,
                  color: const Color(0xFF2B6BFF),
                  onTap: onEdit,
                ),
                const SizedBox(width: 8),
                _ExpenseActionButton(
                  width: 48,
                  label: '',
                  icon: Icons.delete_outline_rounded,
                  color: const Color(0xFFE53935),
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseCell extends StatelessWidget {
  const _ExpenseCell(this.text, {this.color, this.weight});

  final String text;
  final Color? color;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: weight ?? FontWeight.w500,
          color: color ?? Colors.white,
        ),
      ),
    );
  }
}

class _ExpenseActionButton extends StatelessWidget {
  const _ExpenseActionButton({
    required this.width,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final double width;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 38,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: label.isEmpty
            ? Icon(icon, size: 18)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ExpensesPagination extends StatelessWidget {
  const _ExpensesPagination({
    required this.totalItems,
    required this.safePage,
    required this.totalPages,
    required this.onPrev,
    required this.onNext,
  });

  final int totalItems;
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
        children: [
          Text('Jami: $totalItems'),
          const SizedBox(width: 18),
          Text('Sahifa: $safePage / $totalPages'),
          const Spacer(),
          SizedBox(
            width: 44,
            height: 40,
            child: FilledButton.tonal(
              onPressed: onPrev,
              child: const Text('<'),
            ),
          ),
          const SizedBox(width: 8),
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
