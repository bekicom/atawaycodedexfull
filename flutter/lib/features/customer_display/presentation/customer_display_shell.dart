import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class _DisplayPalette {
  static const bgTop = Color(0xFFFFFCF8);
  static const bgBottom = Color(0xFFFFF4EC);
  static const panel = Color(0xFFFFFCF8);
  static const panelBorder = Color(0xFFFFC79B);
  static const textStrong = Color(0xFF6B2C08);
  static const textSoft = Color(0xFFA75B27);
  static const orange = Color(0xFFFF7A2F);
  static const orangeDark = Color(0xFFE45A1E);
  static const cream = Color(0xFFFFF2E4);
  static const yellow = Color(0xFFFFC933);
}

class CustomerDisplayShell extends StatelessWidget {
  const CustomerDisplayShell({
    super.key,
    required this.initialApiBaseUrl,
    this.initialCashierUsername = '',
  });

  final String initialApiBaseUrl;
  final String initialCashierUsername;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mijoz ekrani',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _DisplayPalette.bgTop,
        fontFamily: 'Segoe UI',
      ),
      home: _CustomerDisplayPage(
        initialApiBaseUrl: initialApiBaseUrl,
        initialCashierUsername: initialCashierUsername,
      ),
    );
  }
}

class _CustomerDisplayPage extends StatefulWidget {
  const _CustomerDisplayPage({
    required this.initialApiBaseUrl,
    required this.initialCashierUsername,
  });

  final String initialApiBaseUrl;
  final String initialCashierUsername;

  @override
  State<_CustomerDisplayPage> createState() => _CustomerDisplayPageState();
}

class _CustomerDisplayPageState extends State<_CustomerDisplayPage> {
  late final TextEditingController _backendController = TextEditingController(
    text: widget.initialApiBaseUrl,
  );
  final ScrollController _itemsScrollController = ScrollController();
  final _money = NumberFormat('#,##0', 'uz');
  io.Socket? _socket;
  List<String> _cashiers = [];
  String _selectedCashier = '';
  String _statusText = 'Ulanmoqda...';
  String _errorText = '';
  bool _loading = true;
  _DisplayState _state = const _DisplayState.empty();

  @override
  void initState() {
    super.initState();
    _selectedCashier = widget.initialCashierUsername;
    _restore();
  }

  @override
  void dispose() {
    _socket?.dispose();
    _backendController.dispose();
    _itemsScrollController.dispose();
    super.dispose();
  }

  void _scrollItemsToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_itemsScrollController.hasClients) return;
      final target = _itemsScrollController.position.maxScrollExtent;
      _itemsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('customer_display_backend_url');
    final savedCashier = prefs.getString('customer_display_cashier');
    if ((widget.initialApiBaseUrl.trim().isEmpty) &&
        savedUrl != null &&
        savedUrl.isNotEmpty) {
      _backendController.text = savedUrl;
    }
    if (_selectedCashier.isEmpty &&
        savedCashier != null &&
        savedCashier.isNotEmpty) {
      _selectedCashier = savedCashier;
    }
    await _fetchCashiers(connectAfter: true);
  }

  String _socketBaseUrl() {
    final trimmed = _backendController.text.trim();
    return trimmed.endsWith('/api')
        ? trimmed.substring(0, trimmed.length - 4)
        : trimmed;
  }

  Future<void> _fetchCashiers({bool connectAfter = false}) async {
    try {
      final dio = Dio(BaseOptions(baseUrl: _backendController.text.trim()));
      final response = await dio.get<Map<String, dynamic>>('/auth/login-users');
      final raw = (response.data?['users'] as List?) ?? const [];
      final cashiers =
          raw
              .whereType<Map>()
              .where((item) => item['role']?.toString() == 'cashier')
              .map((item) => item['username']?.toString() ?? '')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      setState(() {
        _cashiers = cashiers;
        if (_selectedCashier.isEmpty && cashiers.isNotEmpty) {
          _selectedCashier = cashiers.first;
        }
        _loading = false;
        _errorText = '';
      });
      if (connectAfter && _selectedCashier.isNotEmpty) {
        await _connect();
      }
    } catch (_) {
      setState(() {
        _loading = false;
        _errorText = 'Kassirlar ro‘yxatini olib bo‘lmadi';
      });
      if (connectAfter && _selectedCashier.isNotEmpty) {
        await _connect();
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'customer_display_backend_url',
      _backendController.text.trim(),
    );
    await prefs.setString('customer_display_cashier', _selectedCashier);
  }

  Future<void> _connect() async {
    if (_selectedCashier.isEmpty) return;
    await _saveSettings();
    _socket?.dispose();
    final socket = io.io(_socketBaseUrl(), {
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
    });
    socket.onConnect((_) {
      if (!mounted) return;
      setState(() => _statusText = 'Jonli ulandi');
      socket.emit('display:join', {'cashierUsername': _selectedCashier});
    });
    socket.onDisconnect((_) {
      if (!mounted) return;
      setState(() => _statusText = 'Ulanish uzildi');
    });
    socket.on('display:state', (payload) {
      if (!mounted || payload is! Map) return;
      setState(() {
        _state = _DisplayState.fromJson(Map<String, dynamic>.from(payload));
      });
      _scrollItemsToLatest();
    });
    socket.onConnectError((_) {
      if (!mounted) return;
      setState(() {
        _statusText = 'Socket ulanmagan';
        _errorText = 'Socket serverga ulanib bo‘lmadi';
      });
    });
    socket.connect();
    _socket = socket;
  }

  Future<void> _showSettingsDialog() async {
    final controller = TextEditingController(text: _backendController.text);
    String selectedCashier = _selectedCashier;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mijoz ekrani sozlamalari'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Backend manzili',
                  hintText: 'http://127.0.0.1:4000/api',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCashier.isEmpty ? null : selectedCashier,
                items: _cashiers
                    .map(
                      (cashier) => DropdownMenuItem(
                        value: cashier,
                        child: Text(cashier),
                      ),
                    )
                    .toList(),
                onChanged: (value) => selectedCashier = value ?? '',
                decoration: const InputDecoration(labelText: 'Kassa tanlang'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () async {
              _backendController.text = controller.text.trim();
              _selectedCashier = selectedCashier;
              Navigator.of(dialogContext).pop();
              await _fetchCashiers(connectAfter: true);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = _DisplayPalette.textStrong;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math
              .min(constraints.maxWidth / 1024, constraints.maxHeight / 768)
              .clamp(0.76, 1.0);
          final gap = 16.0 * scale;
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_DisplayPalette.bgTop, _DisplayPalette.bgBottom],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16 * scale),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mijoz ekrani',
                                style: TextStyle(
                                  fontSize: 28 * scale,
                                  fontWeight: FontWeight.w900,
                                  color: titleColor,
                                ),
                              ),
                              SizedBox(height: 8 * scale),
                              Text(
                                'Kuzatilayotgan kassa: ${_selectedCashier.isEmpty ? 'tanlanmagan' : _selectedCashier}',
                                style: TextStyle(
                                  fontSize: 16 * scale,
                                  fontWeight: FontWeight.w800,
                                  color: _DisplayPalette.textSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _StatusPill(
                          scale: scale,
                          statusText: _statusText,
                          connected: _socket?.connected == true,
                          onSettings: _showSettingsDialog,
                        ),
                      ],
                    ),
                    if (_errorText.isNotEmpty) ...[
                      SizedBox(height: 10 * scale),
                      _GlassPanel(
                        scale: scale,
                        child: Text(
                          _errorText,
                          style: TextStyle(
                            color: Color(0xFFB04343),
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: gap),
                    Row(
                      children: [
                        Expanded(
                          child: _InfoCard(
                            scale: scale,
                            icon: Icons.shopping_basket_rounded,
                            title: 'Mahsulotlar soni',
                            value: '${_state.totalItems}',
                            iconColor: _DisplayPalette.orange,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: _InfoCard(
                            scale: scale,
                            icon: Icons.credit_card_rounded,
                            title: 'To‘lov turi',
                            value: _paymentTypeLabel(_state.paymentType),
                            iconColor: _DisplayPalette.orangeDark,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: _InfoCard(
                            scale: scale,
                            icon: Icons.account_balance_wallet_rounded,
                            title: 'Jami summa',
                            value: '${_money.format(_state.totalAmount)} so‘m',
                            iconColor: _DisplayPalette.yellow,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      child: _GlassPanel(
                        scale: scale,
                        padding: EdgeInsets.all(10 * scale),
                        child: _state.items.isEmpty
                            ? _EmptyDisplayArtwork(scale: scale)
                            : Column(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10 * scale,
                                      vertical: 10 * scale,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.78,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        16 * scale,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        _HeaderCell(
                                          flex: 1,
                                          label: 'No',
                                          align: TextAlign.center,
                                          scale: scale,
                                        ),
                                        _HeaderCell(
                                          flex: 5,
                                          label: 'Mahsulot',
                                          scale: scale,
                                        ),
                                        _HeaderCell(
                                          flex: 2,
                                          label: 'Miqdor',
                                          align: TextAlign.center,
                                          scale: scale,
                                        ),
                                        _HeaderCell(
                                          flex: 2,
                                          label: 'Narxi',
                                          align: TextAlign.center,
                                          scale: scale,
                                        ),
                                        _HeaderCell(
                                          flex: 2,
                                          label: 'Jami',
                                          align: TextAlign.center,
                                          scale: scale,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 8 * scale),
                                  Expanded(
                                    child: ListView.separated(
                                      controller: _itemsScrollController,
                                      itemCount: _state.items.length,
                                      separatorBuilder: (_, _) =>
                                          SizedBox(height: 7 * scale),
                                      itemBuilder: (context, index) {
                                        final item = _state.items[index];
                                        return Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12 * scale,
                                            vertical: 10 * scale,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _DisplayPalette.panel,
                                            borderRadius: BorderRadius.circular(
                                              15 * scale,
                                            ),
                                            border: Border.all(
                                              color:
                                                  _DisplayPalette.panelBorder,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 1,
                                                child: Text(
                                                  '${index + 1}',
                                                  textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: math.max(
                                                      18,
                                                      17 * scale,
                                                    ),
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: _DisplayPalette
                                                        .textStrong,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 5,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.productName,
                                                      style: TextStyle(
                                                        fontSize: math.max(
                                                          22,
                                                          20 * scale,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: _DisplayPalette
                                                            .textStrong,
                                                      ),
                                                    ),
                                                    if (item
                                                        .variantLabel
                                                        .isNotEmpty)
                                                      Text(
                                                        item.variantLabel,
                                                        style: TextStyle(
                                                          fontSize: math.max(
                                                            16,
                                                            14 * scale,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: _DisplayPalette
                                                              .textSoft,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  item.unit.isNotEmpty &&
                                                          item.unit != 'dona'
                                                      ? '${item.quantity} ${item.unit}'
                                                      : '${item.quantity}',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: math.max(
                                                      18,
                                                      16 * scale,
                                                    ),
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: _DisplayPalette
                                                        .textStrong,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _money.format(item.unitPrice),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: math.max(
                                                      18,
                                                      16 * scale,
                                                    ),
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color: _DisplayPalette
                                                        .textStrong,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '${_money.format(item.lineTotal)} so‘m',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: math.max(
                                                      20,
                                                      18 * scale,
                                                    ),
                                                    fontWeight: FontWeight.w900,
                                                    color: _DisplayPalette
                                                        .textStrong,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(height: 8 * scale),
                                  Row(
                                    children: [
                                      const Spacer(),
                                      Text(
                                        'Jami:',
                                        style: TextStyle(
                                          fontSize: math.max(24, 21 * scale),
                                          fontWeight: FontWeight.w800,
                                          color: _DisplayPalette.textSoft,
                                        ),
                                      ),
                                      SizedBox(width: 14 * scale),
                                      Text(
                                        '${_money.format(_state.totalAmount)} so‘m',
                                        style: TextStyle(
                                          fontSize: math.max(30, 28 * scale),
                                          fontWeight: FontWeight.w900,
                                          color: _DisplayPalette.textStrong,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.scale,
    required this.statusText,
    required this.connected,
    required this.onSettings,
  });

  final double scale;
  final String statusText;
  final bool connected;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12 * scale, sigmaY: 12 * scale),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14 * scale,
            vertical: 8 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _DisplayPalette.panelBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16 * scale,
                height: 16 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? const Color(0xFF38C45A)
                      : const Color(0xFFF0A229),
                ),
              ),
              SizedBox(width: 12 * scale),
              Text(
                'Holat: $statusText',
                style: TextStyle(
                  color: _DisplayPalette.textStrong,
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 12 * scale),
              IconButton(
                onPressed: onSettings,
                icon: Icon(
                  Icons.settings_rounded,
                  size: 24 * scale,
                  color: _DisplayPalette.orangeDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.scale = 1,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final double scale;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16 * scale, sigmaY: 16 * scale),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(color: _DisplayPalette.panelBorder, width: 1.2),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EmptyDisplayArtwork extends StatelessWidget {
  const _EmptyDisplayArtwork({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18 * scale),
      child: Container(
        color: const Color(0xFFF8F7F5),
        child: Opacity(
          opacity: 0.34,
          child: Image.asset(
            'assets/branding/ataway_customer_display.jpg',
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.scale,
    required this.icon,
    required this.title,
    required this.value,
    required this.iconColor,
  });

  final double scale;
  final IconData icon;
  final String title;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      scale: scale,
      padding: EdgeInsets.symmetric(
        horizontal: 16 * scale,
        vertical: 12 * scale,
      ),
      child: Row(
        children: [
          Container(
            width: 52 * scale,
            height: 52 * scale,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(18 * scale),
            ),
            child: Icon(icon, color: Colors.white, size: 26 * scale),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w700,
                    color: _DisplayPalette.textSoft,
                  ),
                ),
                SizedBox(height: 6 * scale),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.w900,
                    color: _DisplayPalette.textStrong,
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

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.flex,
    required this.label,
    this.scale = 1,
    this.align = TextAlign.left,
  });

  final int flex;
  final String label;
  final double scale;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(
          fontSize: math.max(18, 16 * scale),
          fontWeight: FontWeight.w900,
          color: _DisplayPalette.textStrong,
        ),
      ),
    );
  }
}

class _DisplayState {
  const _DisplayState({
    required this.paymentType,
    required this.totalAmount,
    required this.totalItems,
    required this.items,
  });

  const _DisplayState.empty()
    : paymentType = '',
      totalAmount = 0,
      totalItems = 0,
      items = const [];

  final String paymentType;
  final double totalAmount;
  final int totalItems;
  final List<_DisplayItem> items;

  factory _DisplayState.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['cartItems'] as List?) ?? const [];
    return _DisplayState(
      paymentType: json['paymentType']?.toString() ?? '',
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      totalItems: (json['totalItems'] as num?)?.toInt() ?? 0,
      items: rawItems
          .whereType<Map>()
          .map((item) => _DisplayItem.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class _DisplayItem {
  const _DisplayItem({
    required this.productName,
    required this.variantLabel,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final String variantLabel;
  final int quantity;
  final String unit;
  final double unitPrice;
  final double lineTotal;

  factory _DisplayItem.fromJson(Map<String, dynamic> json) {
    return _DisplayItem(
      productName: json['productName']?.toString() ?? '',
      variantLabel: json['variantLabel']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unit: json['unit']?.toString() ?? 'dona',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['lineTotal'] as num?)?.toDouble() ?? 0,
    );
  }
}

String _paymentTypeLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Naqd pul';
    case 'card':
      return 'Karta';
    case 'click':
      return 'Click';
    case 'mixed':
      return 'Aralash';
    case 'debt':
      return 'Qarz';
    default:
      return 'Tanlanmagan';
  }
}
