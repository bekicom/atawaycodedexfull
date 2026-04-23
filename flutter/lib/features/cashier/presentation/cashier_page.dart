import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../customers/data/customers_repository.dart';
import '../../customers/domain/customer_record.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product_record.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sales_history_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';
import '../../shifts/data/shifts_repository.dart';
import '../../shifts/domain/shift_record.dart';

class CashierPage extends ConsumerStatefulWidget {
  const CashierPage({super.key});

  @override
  ConsumerState<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends ConsumerState<CashierPage> {
  final _timeFormat = DateFormat('HH:mm');
  final _dateFormat = DateFormat('dd.MM.yyyy');
  final _moneyFormat = NumberFormat('#,##0', 'uz');
  final _barcodeController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  late DateTime _now;
  final List<_CartLine> _cartLines = [];
  final List<_HeldCart> _heldCarts = [];
  bool _isSearching = false;
  int? _selectedLineIndex;
  String _pendingQuantity = '';
  bool _isMultiplyMode = false;
  String? _selectedPaymentType;
  bool _isSubmittingSale = false;
  ShiftRecord? _currentShift;
  bool _isShiftLoading = true;
  bool _isShiftActionLoading = false;
  bool _keepBarcodeFocus = true;
  int _heldCartCounter = 1;
  io.Socket? _displaySocket;
  String _displaySocketUsername = '';
  bool _customerDisplayLaunchAttempted = false;

  String _buildCashDrawerPowerShell(String printerName) {
    final encodedPrinterName = jsonEncode(printerName);
    return '''
\$ErrorActionPreference = 'Stop'
\$preferredPrinter = $encodedPrinterName

if ([string]::IsNullOrWhiteSpace(\$preferredPrinter)) {
  throw 'Default printer topilmadi'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class RawPrinterHelper {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public class DOCINFO {
    [MarshalAs(UnmanagedType.LPWStr)]
    public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)]
    public string pDataType;
  }

  [DllImport("winspool.Drv", EntryPoint="OpenPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);

  [DllImport("winspool.Drv", EntryPoint="ClosePrinter", SetLastError=true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);

  [DllImport("winspool.Drv", EntryPoint="StartDocPrinterW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, Int32 level, DOCINFO di);

  [DllImport("winspool.Drv", EntryPoint="EndDocPrinter", SetLastError=true)]
  public static extern bool EndDocPrinter(IntPtr hPrinter);

  [DllImport("winspool.Drv", EntryPoint="StartPagePrinter", SetLastError=true)]
  public static extern bool StartPagePrinter(IntPtr hPrinter);

  [DllImport("winspool.Drv", EntryPoint="EndPagePrinter", SetLastError=true)]
  public static extern bool EndPagePrinter(IntPtr hPrinter);

  [DllImport("winspool.Drv", EntryPoint="WritePrinter", SetLastError=true)]
  public static extern bool WritePrinter(IntPtr hPrinter, byte[] bytes, Int32 count, out Int32 written);
}
"@

\$handle = [IntPtr]::Zero
if (-not [RawPrinterHelper]::OpenPrinter(\$preferredPrinter, [ref]\$handle, [IntPtr]::Zero)) {
  throw "Printer ochilmadi: \$preferredPrinter"
}

try {
  \$doc = New-Object RawPrinterHelper+DOCINFO
  \$doc.pDocName = 'OpenCashDrawer'
  \$doc.pDataType = 'RAW'

  if (-not [RawPrinterHelper]::StartDocPrinter(\$handle, 1, \$doc)) {
    throw 'StartDocPrinter xatosi'
  }

  try {
    if (-not [RawPrinterHelper]::StartPagePrinter(\$handle)) {
      throw 'StartPagePrinter xatosi'
    }

    try {
      [byte[]]\$bytes = 27,112,0,25,250
      \$written = 0
      if (-not [RawPrinterHelper]::WritePrinter(\$handle, \$bytes, \$bytes.Length, [ref]\$written)) {
        throw 'WritePrinter xatosi'
      }
    } finally {
      [void][RawPrinterHelper]::EndPagePrinter(\$handle)
    }
  } finally {
    [void][RawPrinterHelper]::EndDocPrinter(\$handle)
  }
} finally {
  [void][RawPrinterHelper]::ClosePrinter(\$handle)
}

Write-Output \$preferredPrinter
''';
  }

  Future<String> _resolveReceiptPrinterName() async {
    final printers = await Printing.listPrinters();
    final Printer? printer = printers.cast<Printer?>().firstWhere(
      (item) => item?.isDefault == true,
      orElse: () => printers.isNotEmpty ? printers.first : null,
    );
    return printer?.name ?? '';
  }

  Future<Map<String, dynamic>> _openCashDrawerLocally() async {
    if (!Platform.isWindows) {
      throw Exception('Mahalliy pul qutisi faqat Windows uchun sozlangan');
    }

    final printerName = await _resolveReceiptPrinterName();
    if (printerName.trim().isEmpty) {
      throw Exception('Default printer topilmadi');
    }

    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      _buildCashDrawerPowerShell(printerName),
    ], runInShell: false);

    if (result.exitCode != 0) {
      final message = (result.stderr ?? '').toString().trim();
      throw Exception(message.isEmpty ? 'Pul qutisi ochilmadi' : message);
    }

    return {'ok': true, 'printerName': (result.stdout ?? '').toString().trim()};
  }

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _startClock();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadCurrentShift();
        _ensureDisplaySocketConnected();
        _ensureCustomerDisplayLaunched();
        _barcodeFocusNode.requestFocus();
      }
    });
  }

  Future<void> _startClock() async {
    while (mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
      });
      if (_keepBarcodeFocus && _currentShift != null && mounted) {
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  @override
  void dispose() {
    _displaySocket?.dispose();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  String _displaySocketUrl() {
    final baseUrl = ref.read(apiBaseUrlProvider);
    return baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
  }

  void _ensureDisplaySocketConnected() {
    final session = ref.read(authControllerProvider).valueOrNull;
    final username = session?.user.username ?? '';
    if (username.isEmpty) return;
    if (_displaySocket != null && _displaySocketUsername == username) {
      return;
    }

    _displaySocket?.dispose();
    _displaySocketUsername = username;
    final socket = io.io(_displaySocketUrl(), <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
    });
    socket.onConnect((_) {
      _broadcastCustomerDisplayState();
    });
    socket.connect();
    _displaySocket = socket;
  }

  void _broadcastCustomerDisplayState() {
    final session = ref.read(authControllerProvider).valueOrNull;
    final username = session?.user.username ?? _displaySocketUsername;
    if (username.isEmpty) return;
    _ensureDisplaySocketConnected();
    _displaySocket?.emit('cart:update', {
      'cashierUsername': username,
      'shiftOpen': _currentShift != null,
      'paymentType': _selectedPaymentType ?? '',
      'totalAmount': _cartLines.fold<double>(
        0,
        (sum, line) => sum + line.lineTotal,
      ),
      'totalItems': _cartLines.fold<int>(0, (sum, line) => sum + line.quantity),
      'cartItems': _cartLines
          .map(
            (line) => {
              'productName': line.product.name,
              'variantLabel': line.variantLabel,
              'quantity': line.quantity,
              'unit': line.saleUnit.isNotEmpty
                  ? line.saleUnit
                  : line.product.unit,
              'unitPrice': line.unitPrice,
              'lineTotal': line.lineTotal,
            },
          )
          .toList(),
    });
  }

  Future<void> _ensureCustomerDisplayLaunched() async {
    if (_customerDisplayLaunchAttempted) return;
    final session = ref.read(authControllerProvider).valueOrNull;
    final username = session?.user.username.trim() ?? '';
    if (username.isEmpty) return;
    _customerDisplayLaunchAttempted = true;
    try {
      await Process.start(Platform.resolvedExecutable, [
        '--customer-display',
        '--cashier=$username',
      ], mode: ProcessStartMode.detached);
    } catch (_) {
      _customerDisplayLaunchAttempted = false;
    }
  }

  int _variantStock(ProductRecord product, String size, String color) {
    final variant = product.variantStocks
        .where((item) {
          return item.size == size && item.color == color;
        })
        .cast<ProductVariantRecord?>()
        .firstWhere((item) => item != null, orElse: () => null);
    return (variant?.quantity ?? 0).floor();
  }

  bool _supportsPieceSale(ProductRecord product) {
    final unit = product.unit.trim().toLowerCase();
    return product.allowPieceSale &&
        (unit == 'qop' || unit == 'pachka') &&
        product.pieceQtyPerBase > 0 &&
        product.piecePrice > 0;
  }

  double _reservedBaseQuantity({
    required ProductRecord product,
    required String variantSize,
    required String variantColor,
    int? skipIndex,
  }) {
    var reserved = 0.0;
    for (var i = 0; i < _cartLines.length; i += 1) {
      if (skipIndex != null && i == skipIndex) continue;
      final line = _cartLines[i];
      if (line.product.id != product.id) continue;
      if (line.variantSize != variantSize ||
          line.variantColor != variantColor) {
        continue;
      }
      reserved += line.quantity * line.stockPerUnitInBase;
    }
    return reserved;
  }

  int _maxQuantityForCandidate({
    required ProductRecord product,
    required String variantSize,
    required String variantColor,
    required double stockPerUnitInBase,
    int? skipIndex,
  }) {
    if (stockPerUnitInBase <= 0) return 0;

    final totalBaseStock = variantSize.isNotEmpty || variantColor.isNotEmpty
        ? _variantStock(product, variantSize, variantColor).toDouble()
        : product.quantity;
    final reservedBase = _reservedBaseQuantity(
      product: product,
      variantSize: variantSize,
      variantColor: variantColor,
      skipIndex: skipIndex,
    );
    final availableBase = totalBaseStock - reservedBase;
    if (availableBase <= 0) return 0;

    return math.max(0, (availableBase / stockPerUnitInBase).floor());
  }

  List<ProductVariantRecord> _buildSelectableVariants(ProductRecord product) {
    final fromStocks = product.variantStocks
        .where((item) => item.quantity > 0)
        .toList();
    if (fromStocks.isNotEmpty) {
      fromStocks.sort((a, b) {
        final sizeCompare = a.size.compareTo(b.size);
        if (sizeCompare != 0) return sizeCompare;
        return a.color.compareTo(b.color);
      });
      return fromStocks;
    }

    final sizes = product.sizeOptions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final colors = product.colorOptions
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (sizes.isEmpty && colors.isEmpty) {
      return const <ProductVariantRecord>[];
    }

    final normalizedSizes = sizes.isEmpty ? const [''] : sizes;
    final normalizedColors = colors.isEmpty ? const [''] : colors;
    final generated = <ProductVariantRecord>[];

    for (final size in normalizedSizes) {
      for (final color in normalizedColors) {
        generated.add(
          ProductVariantRecord(
            size: size,
            color: color,
            quantity: product.quantity,
          ),
        );
      }
    }

    return generated;
  }

  bool _hasSelectableVariants(ProductRecord product) {
    final variants = _buildSelectableVariants(product);
    return variants.length > 1 ||
        (variants.length == 1 &&
            (_variantDisplayLabel(variants.first).trim().isNotEmpty &&
                _variantDisplayLabel(variants.first) != 'Variant'));
  }

  String _variantDisplayLabel(ProductVariantRecord variant) {
    final size = variant.size.trim();
    final color = variant.color.trim();
    if (size.isNotEmpty && color.isNotEmpty) return '$size / $color';
    if (color.isNotEmpty) return color;
    if (size.isNotEmpty) return size;
    return 'Variant';
  }

  Future<ProductVariantRecord?> _pickVariantForProduct(
    ProductRecord product,
  ) async {
    final variants = _buildSelectableVariants(product);
    if (variants.isEmpty) {
      return null;
    }
    if (variants.length == 1) {
      return variants.first;
    }

    _keepBarcodeFocus = false;
    ProductVariantRecord? selectedVariant;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 180,
                vertical: 80,
              ),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 760,
                  maxHeight: 620,
                ),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFEFF),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFB7D1F2),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F1E3D),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Qaysi rang yoki variant sotilishini tanlang',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5A7399),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.65,
                            ),
                        itemCount: variants.length,
                        itemBuilder: (context, index) {
                          final variant = variants[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              selectedVariant = variant;
                              Navigator.of(context).pop();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF4FF),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFFBFD7F5),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _variantDisplayLabel(variant),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF163153),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    'Qoldiq: ${variant.quantity.floor()} dona',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF47658E),
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
            );
          },
        );
      },
    );

    _keepBarcodeFocus = true;
    _barcodeFocusNode.requestFocus();
    return selectedVariant;
  }

  Future<_PieceSaleSelection?> _showPieceSaleSelectionDialog(
    ProductRecord product, {
    required int defaultQuantity,
  }) async {
    final quantityController = TextEditingController(
      text: defaultQuantity <= 0 ? '1' : '$defaultQuantity',
    );
    var sellAsPiece = false;

    final result = await showDialog<_PieceSaleSelection>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(product.name),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Qaysi birlikda sotiladi?',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Pachka (${product.unit})'),
                    value: false,
                    groupValue: sellAsPiece,
                    onChanged: (value) {
                      setModalState(() {
                        sellAsPiece = value == true;
                      });
                    },
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Dona (${product.pieceUnit})'),
                    subtitle: Text(
                      '1 ${product.unit} = ${_formatQty(product.pieceQtyPerBase)} ${product.pieceUnit}',
                    ),
                    value: true,
                    groupValue: sellAsPiece,
                    onChanged: (value) {
                      setModalState(() {
                        sellAsPiece = value == true;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _MiniKeyboardButton(
                        onTap: () async {
                          await _openVirtualKeyboard(
                            controller: quantityController,
                            title: sellAsPiece
                                ? '${product.pieceUnit} soni'
                                : '${product.unit} soni',
                            keyboardType: TextInputType.number,
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: quantityController,
                          keyboardType: TextInputType.number,
                          readOnly: true,
                          onTap: () async {
                            await _openVirtualKeyboard(
                              controller: quantityController,
                              title: sellAsPiece
                                  ? '${product.pieceUnit} soni'
                                  : '${product.unit} soni',
                              keyboardType: TextInputType.number,
                            );
                          },
                          decoration: InputDecoration(
                            labelText: sellAsPiece
                                ? '${product.pieceUnit} soni'
                                : '${product.unit} soni',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Bekor'),
                ),
                FilledButton(
                  onPressed: () {
                    final quantity = int.tryParse(
                      quantityController.text.trim(),
                    );
                    if (quantity == null || quantity <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Miqdor 0 dan katta bo‘lishi kerak'),
                          backgroundColor: Color(0xFFC0392B),
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      _PieceSaleSelection(
                        sellAsPiece: sellAsPiece,
                        quantity: quantity,
                      ),
                    );
                  },
                  child: const Text('Qo‘shish'),
                ),
              ],
            );
          },
        );
      },
    );

    quantityController.dispose();
    return result;
  }

  Future<void> _addProductToCart(
    ProductRecord product, {
    int quantity = 1,
    ProductVariantRecord? variant,
  }) async {
    if (quantity <= 0) return;

    var requestedQuantity = quantity;
    var saleUnit = product.unit;
    var saleMode = 'base';
    var stockPerUnitInBase = 1.0;
    double? fixedUnitPrice;

    if (variant == null && _supportsPieceSale(product)) {
      final selection = await _showPieceSaleSelectionDialog(
        product,
        defaultQuantity: quantity,
      );
      if (selection == null) return;
      requestedQuantity = selection.quantity;
      if (selection.sellAsPiece) {
        saleMode = 'piece';
        saleUnit = product.pieceUnit;
        stockPerUnitInBase = 1 / product.pieceQtyPerBase;
        fixedUnitPrice = product.piecePrice;
      }
    }

    final variantSize = variant?.size ?? '';
    final variantColor = variant?.color ?? '';
    final stockLimit = _maxQuantityForCandidate(
      product: product,
      variantSize: variantSize,
      variantColor: variantColor,
      stockPerUnitInBase: stockPerUnitInBase,
    );
    if (stockLimit <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bu mahsulot omborda qolmagan (${saleUnit})'),
          backgroundColor: Color(0xFFC0392B),
        ),
      );
      return;
    }

    var limitedByStock = false;
    setState(() {
      final index = _cartLines.indexWhere(
        (line) =>
            line.product.id == product.id &&
            line.variantSize == variantSize &&
            line.variantColor == variantColor &&
            line.saleMode == saleMode,
      );
      if (index >= 0) {
        final current = _cartLines[index];
        final maxForLine = _maxQuantityForCandidate(
          product: product,
          variantSize: variantSize,
          variantColor: variantColor,
          stockPerUnitInBase: current.stockPerUnitInBase,
          skipIndex: index,
        );
        final nextQuantity = current.quantity + requestedQuantity;
        final safeQuantity = nextQuantity > maxForLine
            ? maxForLine
            : nextQuantity;
        limitedByStock = safeQuantity != nextQuantity;
        _cartLines[index] = current.copyWith(
          quantity: safeQuantity,
          stockLimit: maxForLine,
        );
        _selectedLineIndex = index;
      } else {
        final safeQuantity = requestedQuantity > stockLimit
            ? stockLimit
            : requestedQuantity;
        limitedByStock = safeQuantity != requestedQuantity;
        _cartLines.add(
          _CartLine(
            product: product,
            quantity: safeQuantity,
            variantSize: variantSize,
            variantColor: variantColor,
            stockLimit: stockLimit,
            saleUnit: saleUnit,
            saleMode: saleMode,
            stockPerUnitInBase: stockPerUnitInBase,
            fixedUnitPrice: fixedUnitPrice,
          ),
        );
        _selectedLineIndex = _cartLines.length - 1;
      }
      _barcodeController.clear();
      _pendingQuantity = '';
      _isMultiplyMode = false;
    });

    _broadcastCustomerDisplayState();

    if (limitedByStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            variant == null
                ? 'Omborda faqat $stockLimit $saleUnit bor'
                : '${_variantDisplayLabel(variant)} varianti faqat $stockLimit $saleUnit bor',
          ),
          backgroundColor: const Color(0xFFB9770E),
        ),
      );
    }
  }

  Future<void> _openVirtualKeyboard({
    required TextEditingController controller,
    required String title,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onSubmitted,
  }) async {
    _keepBarcodeFocus = false;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _VirtualKeyboardDialog(
        title: title,
        initialValue: controller.text,
        keyboardType: keyboardType,
      ),
    );

    _keepBarcodeFocus = true;
    if (result == null) {
      _barcodeFocusNode.requestFocus();
      return;
    }

    controller
      ..text = result
      ..selection = TextSelection.collapsed(offset: result.length);

    if (onSubmitted != null) {
      onSubmitted(result);
    }
    _barcodeFocusNode.requestFocus();
  }

  Future<ProductRecord?> _pickProductFromWarehouse({
    String title = 'Ombordan mahsulot tanlash',
    String subtitle =
        'Nomi, modeli yoki shtixi bo‘yicha qidiring. Tanlasangiz savatchaga tushadi.',
  }) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return null;

    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    var products = <ProductRecord>[];
    var isLoading = true;
    var errorText = '';
    ProductRecord? selectedProduct;

    Future<void> loadProducts(
      StateSetter setModalState, [
      String query = '',
    ]) async {
      setModalState(() {
        isLoading = true;
        errorText = '';
      });
      try {
        final result = await ref
            .read(productsRepositoryProvider)
            .fetchProducts(token: session.token, searchQuery: query);
        if (!mounted) return;
        setModalState(() {
          products = result;
          isLoading = false;
        });
      } catch (error) {
        if (!mounted) return;
        setModalState(() {
          products = const [];
          isLoading = false;
          errorText = ref
              .read(authControllerProvider.notifier)
              .formatError(error);
        });
      }
    }

    _keepBarcodeFocus = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isLoading && products.isEmpty && errorText.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  loadProducts(setModalState);
                  searchFocusNode.requestFocus();
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 140,
                vertical: 40,
              ),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 860,
                  maxHeight: 700,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCFEFF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFB7D1F2),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 26,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F3FF),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.inventory_2_outlined,
                              size: 30,
                              color: Color(0xFF0F4E8A),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F1E3D),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A7399),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: const Color(0xFF264B77),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        height: 58,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFC8DCF7),
                            width: 1.4,
                          ),
                        ),
                        child: Row(
                          children: [
                            _MiniKeyboardButton(
                              onTap: () async {
                                await _openVirtualKeyboard(
                                  controller: searchController,
                                  title: 'Mahsulot qidirish',
                                );
                                await loadProducts(
                                  setModalState,
                                  searchController.text,
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF6B87AF),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: searchController,
                                focusNode: searchFocusNode,
                                onChanged: (value) =>
                                    loadProducts(setModalState, value),
                                onSubmitted: (value) =>
                                    loadProducts(setModalState, value),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  errorBorder: InputBorder.none,
                                  focusedErrorBorder: InputBorder.none,
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText:
                                      'Nomi, modeli yoki shtix bo‘yicha qidiring',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF7C93B5),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF10203F),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                cursorColor: Color(0xFF10203F),
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
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFD3E3F8)),
                          ),
                          child: isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : errorText.isNotEmpty
                              ? Center(
                                  child: Text(
                                    errorText,
                                    style: const TextStyle(
                                      color: Color(0xFFB03A3A),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              : products.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Mahsulot topilmadi',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF577096),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(14),
                                  itemCount: products.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final product = products[index];
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () {
                                        selectedProduct = product;
                                        Navigator.of(context).pop();
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFBFDFF),
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFD7E6F8),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 52,
                                              height: 52,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE4F2FF),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF0E4E8D),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    product.name,
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Color(0xFF10203F),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 10,
                                                    runSpacing: 6,
                                                    children: [
                                                      _ProductInfoChip(
                                                        label: 'Model',
                                                        value:
                                                            product
                                                                .model
                                                                .isEmpty
                                                            ? '-'
                                                            : product.model,
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Kategoriya',
                                                        value: product
                                                            .category
                                                            .name,
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Omborda',
                                                        value:
                                                            '${product.quantity.toStringAsFixed(product.quantity == product.quantity.roundToDouble() ? 0 : 2)} ${product.unit}',
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Shtix',
                                                        value: product.barcode,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  '${_moneyFormat.format(product.retailPrice)} so‘m',
                                                  style: const TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF0F4E8A),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 10,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF1B88DA,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'Savatchaga qo‘shish',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    _keepBarcodeFocus = true;
    _barcodeFocusNode.requestFocus();
    return selectedProduct;
  }

  Future<void> _openProductPickerModal() async {
    final product = await _pickProductFromWarehouse();
    if (product == null) return;
    final multiplier = _isMultiplyMode
        ? (int.tryParse(_pendingQuantity) ?? 1).clamp(1, 9999)
        : 1;
    ProductVariantRecord? variant;
    if (_hasSelectableVariants(product)) {
      variant = await _pickVariantForProduct(product);
      if (variant == null) return;
    }
    await _addProductToCart(product, quantity: multiplier, variant: variant);
  }

  Future<List<ProductRecord>> _persistTopProducts(
    String token,
    List<ProductRecord> products,
  ) async {
    return ref
        .read(productsRepositoryProvider)
        .saveTopProducts(
          token: token,
          productIds: products.map((item) => item.id).toList(),
        );
  }

  Future<void> _showTopProductsDialog() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;

    var topProducts = <ProductRecord>[];
    var isLoading = true;
    var isSaving = false;
    var errorText = '';

    Future<void> loadTop(StateSetter setModalState) async {
      setModalState(() {
        isLoading = true;
        errorText = '';
      });
      try {
        final result = await ref
            .read(productsRepositoryProvider)
            .fetchTopProducts(token: session.token);
        if (!mounted) return;
        setModalState(() {
          topProducts = result;
          isLoading = false;
        });
      } catch (error) {
        if (!mounted) return;
        setModalState(() {
          errorText = ref
              .read(authControllerProvider.notifier)
              .formatError(error);
          isLoading = false;
        });
      }
    }

    Future<void> saveTopProducts(
      StateSetter setModalState,
      List<ProductRecord> nextProducts,
    ) async {
      setModalState(() {
        isSaving = true;
        errorText = '';
      });
      try {
        final saved = await _persistTopProducts(session.token, nextProducts);
        if (!mounted) return;
        setModalState(() {
          topProducts = saved;
          isSaving = false;
        });
      } catch (error) {
        if (!mounted) return;
        setModalState(() {
          errorText = ref
              .read(authControllerProvider.notifier)
              .formatError(error);
          isSaving = false;
        });
      }
    }

    _keepBarcodeFocus = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            if (isLoading && topProducts.isEmpty && errorText.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  loadTop(setModalState);
                }
              });
            }

            final itemCount = topProducts.length + 1;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 90,
                vertical: 34,
              ),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 1120,
                  maxHeight: 760,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDFEFF),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: const Color(0xFFB7D1F2),
                    width: 1.4,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 28,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7F3FF),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.local_fire_department_rounded,
                              size: 32,
                              color: Color(0xFF0F4E8A),
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOP tavarlar',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F1E3D),
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tez sotiladigan mahsulotlarni bir marta tanlab qo‘ying. Kartani bossangiz savatga tushadi.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A7399),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: const Color(0xFF264B77),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (errorText.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE8E8),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF3B1B1)),
                          ),
                          child: Text(
                            errorText,
                            style: const TextStyle(
                              color: Color(0xFF9F2E2E),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Expanded(
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : GridView.builder(
                                itemCount: itemCount,
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      crossAxisSpacing: 14,
                                      mainAxisSpacing: 14,
                                      mainAxisExtent: 190,
                                    ),
                                itemBuilder: (context, index) {
                                  final product = index < topProducts.length
                                      ? topProducts[index]
                                      : null;
                                  if (product == null) {
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: isSaving
                                          ? null
                                          : () async {
                                              final picked =
                                                  await _pickProductFromWarehouse(
                                                    title:
                                                        'TOP tavarga mahsulot qo‘shish',
                                                    subtitle:
                                                        'Ombordan tez sotiladigan mahsulotni tanlang. Saqlangach TOP ichida turadi.',
                                                  );
                                              if (picked == null) return;
                                              if (topProducts.any(
                                                (item) => item.id == picked.id,
                                              )) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Bu mahsulot allaqachon TOP ro‘yxatida bor',
                                                    ),
                                                    backgroundColor: Color(
                                                      0xFFB9770E,
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              await saveTopProducts(
                                                setModalState,
                                                [...topProducts, picked],
                                              );
                                            },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FBFF),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFCCE0F9),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_rounded,
                                              size: 40,
                                              color: Color(0xFF2A83D3),
                                            ),
                                            SizedBox(height: 10),
                                            Text(
                                              'TOPga qo‘shish',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF1B3A63),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }

                                  return InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () {
                                      final multiplier = _isMultiplyMode
                                          ? (int.tryParse(_pendingQuantity) ??
                                                    1)
                                                .clamp(1, 9999)
                                          : 1;
                                      _addProductToCart(
                                        product,
                                        quantity: multiplier,
                                      );
                                      Navigator.of(dialogContext).pop();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFFD2E3F7),
                                          width: 1.4,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  product.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF10203F),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              InkWell(
                                                onTap: isSaving
                                                    ? null
                                                    : () async {
                                                        final picked =
                                                            await _pickProductFromWarehouse(
                                                              title:
                                                                  'TOP tavarni almashtirish',
                                                              subtitle:
                                                                  'O‘rniga qo‘yiladigan mahsulotni tanlang.',
                                                            );
                                                        if (picked == null)
                                                          return;
                                                        final nextProducts = [
                                                          ...topProducts,
                                                        ];
                                                        nextProducts[index] =
                                                            picked;
                                                        await saveTopProducts(
                                                          setModalState,
                                                          nextProducts,
                                                        );
                                                      },
                                                child: const Icon(
                                                  Icons.edit_rounded,
                                                  color: Color(0xFF2A83D3),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              InkWell(
                                                onTap: isSaving
                                                    ? null
                                                    : () async {
                                                        final nextProducts = [
                                                          ...topProducts,
                                                        ]..removeAt(index);
                                                        await saveTopProducts(
                                                          setModalState,
                                                          nextProducts,
                                                        );
                                                      },
                                                child: const Icon(
                                                  Icons.close_rounded,
                                                  color: Color(0xFFE74C3C),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _ProductInfoChip(
                                                label: 'Omborda',
                                                value:
                                                    '${product.quantity.toStringAsFixed(product.quantity == product.quantity.roundToDouble() ? 0 : 2)} ${product.unit}',
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${_moneyFormat.format(product.retailPrice)} so‘m',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w900,
                                                    color: Color(0xFF0F4E8A),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                width: 44,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFF1B88DA,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: const Icon(
                                                  Icons.shopping_cart_rounded,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                              ),
                                            ],
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
              ),
            );
          },
        );
      },
    );
    _keepBarcodeFocus = true;
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _scanBarcode(String rawValue) async {
    final barcode = rawValue.trim();
    if (barcode.isEmpty || _isSearching) return;
    if (_currentShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avval smenani boshlang')));
      return;
    }

    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;

    final multiplier = _isMultiplyMode
        ? (int.tryParse(_pendingQuantity) ?? 1).clamp(1, 9999)
        : 1;

    setState(() {
      _isSearching = true;
    });

    try {
      final products = await ref
          .read(productsRepositoryProvider)
          .fetchProducts(token: session.token, searchQuery: barcode);

      ProductRecord? product;
      for (final item in products) {
        if (_matchesProductBarcode(item, barcode)) {
          product = item;
          break;
        }
      }
      product ??= products.isNotEmpty ? products.first : null;

      if (product == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mahsulot topilmadi: $barcode'),
            backgroundColor: const Color(0xFFC0392B),
          ),
        );
        return;
      }

      ProductVariantRecord? variant;
      if (_hasSelectableVariants(product)) {
        if (!mounted) return;
        variant = await _pickVariantForProduct(product);
        if (variant == null) return;
      }

      if (!mounted) return;
      await _addProductToCart(product, quantity: multiplier, variant: variant);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authControllerProvider.notifier).formatError(error),
          ),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  bool _matchesProductBarcode(ProductRecord product, String barcode) {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return false;
    if (product.barcode.trim() == normalized) return true;
    return product.barcodeAliases.any((alias) => alias.trim() == normalized);
  }

  void _handleKeypadTap(String value) {
    if (value == '-1') {
      setState(() {
        final selectedIndex = _selectedLineIndex;
        if (selectedIndex != null &&
            selectedIndex >= 0 &&
            selectedIndex < _cartLines.length) {
          final currentLine = _cartLines[selectedIndex];
          final nextQuantity = currentLine.quantity - 1;

          if (nextQuantity <= 0) {
            _cartLines.removeAt(selectedIndex);
            if (_cartLines.isEmpty) {
              _selectedLineIndex = null;
            } else if (selectedIndex >= _cartLines.length) {
              _selectedLineIndex = _cartLines.length - 1;
            }
            _pendingQuantity = '';
          } else {
            _cartLines[selectedIndex] = currentLine.copyWith(
              quantity: nextQuantity,
            );
            _pendingQuantity = '$nextQuantity';
          }
        } else if (_pendingQuantity.isNotEmpty) {
          _pendingQuantity = _pendingQuantity.substring(
            0,
            _pendingQuantity.length - 1,
          );
        }
      });

      _broadcastCustomerDisplayState();
      _barcodeFocusNode.requestFocus();
      return;
    }

    if (value == 'X') {
      setState(() {
        _isMultiplyMode = true;
        _pendingQuantity = '';
      });
      _barcodeFocusNode.requestFocus();
      return;
    }

    if (!RegExp(r'^\d$').hasMatch(value)) return;

    setState(() {
      final raw = '$_pendingQuantity$value';
      final normalized = raw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      _pendingQuantity = normalized;

      final selectedIndex = _selectedLineIndex;
      if (selectedIndex != null &&
          selectedIndex >= 0 &&
          selectedIndex < _cartLines.length) {
        final qty = int.tryParse(_pendingQuantity) ?? 0;
        if (qty > 0) {
          final currentLine = _cartLines[selectedIndex];
          final stockLimit = _maxQuantityForCandidate(
            product: currentLine.product,
            variantSize: currentLine.variantSize,
            variantColor: currentLine.variantColor,
            stockPerUnitInBase: currentLine.stockPerUnitInBase,
            skipIndex: selectedIndex,
          );
          final safeQty = qty > stockLimit ? stockLimit : qty;
          _cartLines[selectedIndex] = currentLine.copyWith(
            quantity: safeQty,
            stockLimit: stockLimit,
          );
          if (safeQty != qty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Omborda faqat $stockLimit ${currentLine.saleUnit} bor',
                  ),
                  backgroundColor: const Color(0xFFB9770E),
                ),
              );
            });
          }
        }
      }
    });

    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  void _selectCartLine(int index) {
    setState(() {
      _selectedLineIndex = index;
      _pendingQuantity = '';
      _isMultiplyMode = false;
    });
  }

  void _removeSelectedLine() {
    final selectedIndex = _selectedLineIndex;
    if (selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= _cartLines.length) {
      return;
    }

    setState(() {
      _cartLines.removeAt(selectedIndex);
      if (_cartLines.isEmpty) {
        _selectedLineIndex = null;
      } else if (selectedIndex >= _cartLines.length) {
        _selectedLineIndex = _cartLines.length - 1;
      }
      _pendingQuantity = '';
      _isMultiplyMode = false;
    });

    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  void _removeLineAt(int index) {
    if (index < 0 || index >= _cartLines.length) return;

    setState(() {
      _cartLines.removeAt(index);
      if (_cartLines.isEmpty) {
        _selectedLineIndex = null;
      } else if (_selectedLineIndex == null) {
        _selectedLineIndex = 0;
      } else if (_selectedLineIndex! >= _cartLines.length) {
        _selectedLineIndex = _cartLines.length - 1;
      }
      _pendingQuantity = '';
      _isMultiplyMode = false;
    });

    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  void _toggleWholesaleAt(int index) {
    if (index < 0 || index >= _cartLines.length) return;

    final currentLine = _cartLines[index];
    if (currentLine.product.wholesalePrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu mahsulot uchun optom narx kiritilmagan'),
          backgroundColor: Color(0xFFB9770E),
        ),
      );
      _barcodeFocusNode.requestFocus();
      return;
    }

    setState(() {
      _cartLines[index] = currentLine.copyWith(
        isWholesale: !currentLine.isWholesale,
      );
      _selectedLineIndex = index;
    });

    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _selectVariantAt(int index) async {
    if (index < 0 || index >= _cartLines.length) return;

    final currentLine = _cartLines[index];
    if (!_hasSelectableVariants(currentLine.product)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu mahsulotda rang/razmer tanlash yo‘q'),
          backgroundColor: Color(0xFFB9770E),
        ),
      );
      _barcodeFocusNode.requestFocus();
      return;
    }

    final variant = await _pickVariantForProduct(currentLine.product);
    if (variant == null) {
      _barcodeFocusNode.requestFocus();
      return;
    }

    setState(() {
      _cartLines[index] = currentLine.copyWith(
        variantSize: variant.size,
        variantColor: variant.color,
        stockLimit: _maxQuantityForCandidate(
          product: currentLine.product,
          variantSize: variant.size,
          variantColor: variant.color,
          stockPerUnitInBase: currentLine.stockPerUnitInBase,
          skipIndex: index,
        ),
      );
      _selectedLineIndex = index;
    });

    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  void _selectPaymentType(String paymentType) {
    setState(() {
      _selectedPaymentType = paymentType;
    });
    _broadcastCustomerDisplayState();
  }

  String _heldCartLabel([DateTime? createdAt]) {
    final stamp = DateFormat('HH:mm').format(createdAt ?? DateTime.now());
    return 'Navbat ${_heldCartCounter++} • $stamp';
  }

  void _storeCurrentCart({String? label}) {
    if (_cartLines.isEmpty) return;
    _heldCarts.insert(
      0,
      _HeldCart(
        label: label ?? _heldCartLabel(),
        createdAt: DateTime.now(),
        lines: _cartLines.map((line) => line.copyWith()).toList(),
        selectedPaymentType: _selectedPaymentType,
      ),
    );
    _cartLines.clear();
    _selectedLineIndex = null;
    _pendingQuantity = '';
    _isMultiplyMode = false;
    _selectedPaymentType = null;
    _barcodeController.clear();
    _broadcastCustomerDisplayState();
  }

  void _restoreHeldCart(_HeldCart heldCart) {
    if (_cartLines.isNotEmpty) {
      _storeCurrentCart(label: _heldCartLabel());
    }
    _cartLines
      ..clear()
      ..addAll(heldCart.lines.map((line) => line.copyWith()));
    _selectedPaymentType = heldCart.selectedPaymentType;
    _selectedLineIndex = _cartLines.isEmpty ? null : 0;
    _pendingQuantity = '';
    _isMultiplyMode = false;
    _heldCarts.removeWhere((item) => item.id == heldCart.id);
    _broadcastCustomerDisplayState();
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _showHeldCartsDialog() async {
    if (_currentShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avval smenani boshlang')));
      return;
    }

    if (_cartLines.isNotEmpty) {
      setState(() {
        _storeCurrentCart();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Savatcha navbatga avtomatik olindi')),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentTotal = _cartLines.fold<double>(
              0,
              (sum, line) => sum + line.lineTotal,
            );

            void refreshModal(void Function() fn) {
              if (!mounted) return;
              setState(fn);
              setModalState(() {});
            }

            return Dialog(
              backgroundColor: const Color(0xFF102245),
              child: Container(
                width: 860,
                constraints: const BoxConstraints(maxHeight: 720),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Savatcha navbati',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Hozirgi mijoz savatini vaqtincha saqlang va keyin qayta oching.',
                                style: TextStyle(
                                  color: Color(0xFFBFD4F5),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white70,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A335F),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF325183)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Hozirgi savatcha',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _cartLines.isEmpty
                                      ? 'Savatcha bo‘sh'
                                      : '${_cartLines.length} ta mahsulot • ${_moneyFormat.format(currentTotal)} so‘m',
                                  style: const TextStyle(
                                    color: Color(0xFFBFD4F5),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF244676),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF3D5E93),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  color: Color(0xFF9BD0FF),
                                  size: 22,
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'NAVBAT avtomatik saqlanadi',
                                  style: TextStyle(
                                    color: Color(0xFFD9ECFF),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A335F),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF325183)),
                        ),
                        child: _heldCarts.isEmpty
                            ? const Center(
                                child: Text(
                                  'Navbatga olingan savatcha yo‘q',
                                  style: TextStyle(
                                    color: Color(0xFFBFD4F5),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: _heldCarts.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final heldCart = _heldCarts[index];
                                  final total = heldCart.lines.fold<double>(
                                    0,
                                    (sum, line) => sum + line.lineTotal,
                                  );
                                  final preview = heldCart.lines
                                      .take(3)
                                      .map((line) => line.product.name)
                                      .join(', ');
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF223F71),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFF3D5E93),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                heldCart.label,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                '${heldCart.lines.length} ta mahsulot • ${_moneyFormat.format(total)} so‘m',
                                                style: const TextStyle(
                                                  color: Color(0xFFBFD4F5),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                preview,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF9CB3D8),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 140,
                                          height: 48,
                                          child: _PrimaryActionBox(
                                            label: 'OCHISH',
                                            icon: Icons.reply_all_rounded,
                                            onTap: () {
                                              setState(() {
                                                _restoreHeldCart(heldCart);
                                              });
                                              Navigator.of(dialogContext).pop();
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        SizedBox(
                                          width: 130,
                                          height: 48,
                                          child: _ActionBox(
                                            label: 'O‘CHIRISH',
                                            icon: Icons.delete_outline_rounded,
                                            onTap: () {
                                              refreshModal(() {
                                                _heldCarts.removeWhere(
                                                  (item) =>
                                                      item.id == heldCart.id,
                                                );
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _submitSale({bool shouldPrintReceipt = true}) async {
    if (_cartLines.isEmpty ||
        _selectedPaymentType == null ||
        _isSubmittingSale) {
      return;
    }
    if (_currentShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avval smenani boshlang')));
      return;
    }

    for (var i = 0; i < _cartLines.length; i += 1) {
      final line = _cartLines[i];
      if (_hasSelectableVariants(line.product) &&
          line.variantLabel.trim().isEmpty) {
        setState(() {
          _selectedLineIndex = i;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${line.product.name} uchun rang/razmer tanlang'),
            backgroundColor: const Color(0xFFB9770E),
          ),
        );
        _barcodeFocusNode.requestFocus();
        return;
      }
    }

    final paymentType = _selectedPaymentType!;
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;

    setState(() {
      _isSubmittingSale = true;
      _keepBarcodeFocus = false;
    });
    _barcodeFocusNode.unfocus();
    _barcodeFocusNode.canRequestFocus = false;

    try {
      final totalAmount = _cartLines.fold<double>(
        0,
        (sum, line) => sum + line.lineTotal,
      );
      Map<String, dynamic>? extraPayload;
      double? cashReceived;
      double? cashChange;

      if (paymentType == 'mixed') {
        extraPayload = await _showMixedPaymentDialog(totalAmount);
        if (extraPayload == null) return;
      } else if (paymentType == 'cash' ||
          paymentType == 'card' ||
          paymentType == 'click') {
        final cashResult = await _showCashPaymentDialog(
          totalAmount,
          paymentType: paymentType,
        );
        if (cashResult == null) return;
        cashReceived = (cashResult['cashReceived'] ?? 0).toDouble();
        cashChange = (cashResult['change'] ?? 0).toDouble();
      } else if (paymentType == 'debt') {
        extraPayload = await _showDebtCustomerDialog(session.token);
        if (extraPayload == null) return;
      }

      final payload = {
        'paymentType': paymentType,
        'items': _cartLines
            .map(
              (line) => {
                'productId': line.product.id,
                'quantity': line.quantity,
                'priceType': line.priceType,
                'unitPrice': line.unitPrice,
                'variantSize': line.variantSize,
                'variantColor': line.variantColor,
                'saleMode': line.saleMode,
                'saleUnit': line.saleUnit,
                'stockPerUnitInBase': line.stockPerUnitInBase,
              },
            )
            .toList(),
        ...?extraPayload,
      };

      final response = await ref
          .read(salesRepositoryProvider)
          .createSale(token: session.token, payload: payload);

      final rawSale = response['sale'];
      final sale = rawSale is Map<String, dynamic>
          ? rawSale
          : rawSale is Map
          ? Map<String, dynamic>.from(rawSale)
          : <String, dynamic>{};
      AppSettingsRecord? settings;
      _ReceiptSaleData? saleData;
      var printedReceipt = false;
      String? receiptError;

      if (shouldPrintReceipt) {
        try {
          settings = await ref
              .read(settingsRepositoryProvider)
              .fetchSettings(session.token);
          saleData = _ReceiptSaleData.fromMap(
            sale,
            fallbackCashierUsername: session.user.username,
          );
          printedReceipt = await _printReceipt(
            settings: settings,
            cashierUsername: session.user.username,
            sale: sale,
          );
          if (printedReceipt) {
            await _openCashDrawer(showSuccessMessage: false);
          }
        } catch (error) {
          receiptError = error.toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _cartLines.clear();
        _selectedLineIndex = null;
        _pendingQuantity = '';
        _isMultiplyMode = false;
        _selectedPaymentType = null;
      });
      _broadcastCustomerDisplayState();

      if (shouldPrintReceipt && mounted && saleData != null) {
        try {
          await _showReceiptPreviewDialog(settings: settings!, sale: saleData);
        } catch (error) {
          receiptError = error.toString();
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            receiptError == null
                ? ((paymentType == 'cash' ||
                              paymentType == 'card' ||
                              paymentType == 'click') &&
                          cashReceived != null &&
                          cashChange != null
                      ? 'Sotuv muvaffaqiyatli yakunlandi. Berilgan: ${_formatMoney(cashReceived)}  Qaytim: ${_formatMoney(cashChange)}'
                      : 'Sotuv muvaffaqiyatli yakunlandi')
                : 'Sotuv saqlandi, lekin chek oynasida xato bor',
          ),
          backgroundColor: receiptError == null
              ? const Color(0xFF1F8F55)
              : const Color(0xFFB9770E),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final authController = ref.read(authControllerProvider.notifier);
      final formatted = authController.formatError(error);
      final fallback = error.toString().trim();
      final message = formatted == 'Xatolik yuz berdi' && fallback.isNotEmpty
          ? fallback
          : formatted;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingSale = false;
        });
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  Future<void> _loadCurrentShift() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;

    try {
      final shift = await ref
          .read(shiftsRepositoryProvider)
          .fetchCurrentShift(session.token);
      if (!mounted) return;
      setState(() {
        _currentShift = shift;
        _isShiftLoading = false;
      });
      _broadcastCustomerDisplayState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isShiftLoading = false;
      });
    }
  }

  Future<void> _openShift() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty || _isShiftActionLoading) {
      return;
    }

    setState(() {
      _isShiftActionLoading = true;
    });
    try {
      final shift = await ref
          .read(shiftsRepositoryProvider)
          .openShift(session.token);
      if (!mounted) return;
      setState(() {
        _currentShift = shift;
      });
      _broadcastCustomerDisplayState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Smena boshlandi: #${shift.shiftNumber}'),
          backgroundColor: const Color(0xFF1F8F55),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authControllerProvider.notifier).formatError(error),
          ),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isShiftActionLoading = false;
          _isShiftLoading = false;
        });
      }
    }
  }

  Future<void> _closeShift() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null ||
        session.token.isEmpty ||
        _isShiftActionLoading ||
        _currentShift == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Smenani tugatish'),
          content: const Text(
            'Haqiqatan ham smenani yopmoqchimisiz? Yopilgandan keyin hisobot tayyor bo\'ladi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yopish'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() {
      _isShiftActionLoading = true;
    });
    try {
      final activeShift = _currentShift!;
      final history = await ref
          .read(salesRepositoryProvider)
          .fetchSales(
            token: session.token,
            period: 'all',
            from: '',
            to: '',
            shiftId: activeShift.id,
          );
      final shift = await ref
          .read(shiftsRepositoryProvider)
          .closeCurrentShift(session.token);
      final report = _ShiftCloseReport.fromSales(
        shift: shift,
        sales: history.sales,
      );
      if (!mounted) return;
      setState(() {
        _currentShift = null;
        _selectedPaymentType = null;
        _cartLines.clear();
        _heldCarts.clear();
        _selectedLineIndex = null;
        _pendingQuantity = '';
        _isMultiplyMode = false;
      });
      _broadcastCustomerDisplayState();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Smena yopildi: #${shift.shiftNumber} | jami ${_moneyFormat.format(shift.totalAmount)}',
          ),
          backgroundColor: const Color(0xFF1F8F55),
        ),
      );
      await _printShiftCloseReport(report);
      await _showShiftClosedReport(report);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authControllerProvider.notifier).formatError(error),
          ),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isShiftActionLoading = false;
          _isShiftLoading = false;
        });
      }
    }
  }

  Future<void> _showShiftClosedReport(_ShiftCloseReport report) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final openedAt = report.shift.openedAt?.toLocal();
        final closedAt = report.shift.closedAt?.toLocal() ?? report.generatedAt;
        return Dialog(
          backgroundColor: const Color(0xFF102245),
          child: Container(
            width: 560,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Smena yopildi',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: Color(0xFF17284B),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'SMENA YAKUNIY HISOBOTI',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _shiftReportLine(
                            'Kassa',
                            'Smena ${report.shift.shiftNumber}',
                          ),
                          _shiftReportLine(
                            'Kassir',
                            report.shift.cashierUsername,
                          ),
                          _shiftReportLine(
                            'Ochildi',
                            openedAt == null
                                ? '-'
                                : DateFormat(
                                    'dd.MM.yyyy HH:mm:ss',
                                  ).format(openedAt),
                          ),
                          _shiftReportLine(
                            'Yopildi',
                            DateFormat('dd.MM.yyyy HH:mm:ss').format(closedAt),
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          const Text(
                            'SOTUVLAR',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          _shiftReportLine(
                            'Sotuvlar soni',
                            '${report.salesReceiptCount}',
                          ),
                          _shiftReportLine(
                            'Sotuv pozitsiyasi',
                            '${report.salesLineCount}',
                          ),
                          _shiftReportLine(
                            'Sotilgan birlik',
                            _formatQty(report.salesUnitCount),
                          ),
                          _shiftReportLine(
                            'Naqd',
                            _formatMoney(report.salesCash),
                          ),
                          _shiftReportLine(
                            'Karta',
                            _formatMoney(report.salesCard),
                          ),
                          _shiftReportLine(
                            'Click',
                            _formatMoney(report.salesClick),
                          ),
                          if (report.salesDebt > 0.0001)
                            _shiftReportLine(
                              'Qarz',
                              _formatMoney(report.salesDebt),
                            ),
                          _shiftReportLine(
                            'Jami summa',
                            _formatMoney(report.salesTotal),
                            emphasized: true,
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          const Text(
                            'QAYTARUVLAR',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          _shiftReportLine(
                            'Qaytaruvlar soni',
                            '${report.returnReceiptCount}',
                          ),
                          _shiftReportLine(
                            'Qaytaruv pozitsiyasi',
                            '${report.returnLineCount}',
                          ),
                          _shiftReportLine(
                            'Qaytgan birlik',
                            _formatQty(report.returnUnitCount),
                          ),
                          _shiftReportLine(
                            'Naqd',
                            _formatMoney(report.returnCash),
                          ),
                          _shiftReportLine(
                            'Karta',
                            _formatMoney(report.returnCard),
                          ),
                          _shiftReportLine(
                            'Click',
                            _formatMoney(report.returnClick),
                          ),
                          _shiftReportLine(
                            'Jami qaytaruv',
                            _formatMoney(report.returnTotal),
                            emphasized: true,
                          ),
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          const Text(
                            'YAKUNIY HOLAT',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          _shiftReportLine(
                            'Naqd',
                            _formatMoney(report.netCash),
                          ),
                          _shiftReportLine(
                            'Karta',
                            _formatMoney(report.netCard),
                          ),
                          _shiftReportLine(
                            'Click',
                            _formatMoney(report.netClick),
                          ),
                          _shiftReportLine(
                            'Yakuniy jami',
                            _formatMoney(report.netTotal),
                            emphasized: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 180,
                    height: 52,
                    child: _PrimaryActionBox(
                      label: 'YOPISH',
                      icon: Icons.check_rounded,
                      onTap: () => Navigator.of(dialogContext).pop(),
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

  String _formatQty(double value) {
    return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  }

  Widget _shiftReportLine(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = TextStyle(
      color: const Color(0xFF17284B),
      fontSize: emphasized ? 14 : 13,
      fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style, textAlign: TextAlign.right),
        ],
      ),
    );
  }

  pw.Widget _buildShiftPdfLine(
    String label,
    String value, {
    bool emphasized = false,
  }) {
    final style = pw.TextStyle(
      fontSize: emphasized ? 10 : 9,
      fontWeight: pw.FontWeight.bold,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.SizedBox(width: 8),
          pw.Text(value, style: style, textAlign: pw.TextAlign.right),
        ],
      ),
    );
  }

  Future<_ReturnResult?> _showReturnSaleDialog({
    required String token,
    required SaleRecord sale,
  }) async {
    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    final quantityControllers = <String, TextEditingController>{};
    final variantSelections = <String, ProductVariantRecord>{};
    _ReturnResult? result;
    var submittingItemId = '';
    var errorText = '';
    var query = '';
    var selectedReturnPaymentType = 'cash';

    final productByBarcode = <String, ProductRecord>{};
    final uniqueBarcodes = sale.items
        .map((item) => item.barcode.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    for (final barcode in uniqueBarcodes) {
      try {
        final products = await ref
            .read(productsRepositoryProvider)
            .fetchProducts(token: token, searchQuery: barcode);
        final matched = products.where(
          (item) => _matchesProductBarcode(item, barcode),
        );
        if (matched.isNotEmpty) {
          productByBarcode[barcode] = matched.first;
        }
      } catch (_) {}
    }

    final groupedItems = _ReturnSaleGroup.aggregate(sale.items);
    for (final item in groupedItems) {
      quantityControllers['${item.productId}:${item.variantSize}:${item.variantColor}:${item.unitPrice}'] =
          TextEditingController();
    }

    Future<void> processReturn(
      StateSetter setModalState,
      _ReturnSaleGroup item,
    ) async {
      final itemKey =
          '${item.productId}:${item.variantSize}:${item.variantColor}:${item.unitPrice}';
      final controller = quantityControllers[itemKey];
      final rawQty = controller?.text.trim() ?? '';
      final quantity = double.tryParse(rawQty.replaceAll(',', '.')) ?? 0;
      final maxQty = item.availableQuantity;
      final selectedVariant = variantSelections[itemKey];
      final fallbackVariants = item.variantLabel.trim().isNotEmpty
          ? const <ProductVariantRecord>[]
          : _buildSelectableVariants(
              productByBarcode[item.barcode] ??
                  const ProductRecord(
                    id: '',
                    name: '',
                    model: '',
                    barcode: '',
                    productCode: '0000',
                    gender: '',
                    category: ProductCategoryRef(id: '', name: ''),
                    supplier: ProductSupplierRef(
                      id: '',
                      name: '',
                      phone: '',
                      address: '',
                    ),
                    purchasePrice: 0,
                    priceCurrency: 'uzs',
                    usdRateUsed: 0,
                    totalPurchaseCost: 0,
                    retailPrice: 0,
                    wholesalePrice: 0,
                    paymentType: 'naqd',
                    paidAmount: 0,
                    debtAmount: 0,
                    quantity: 0,
                    unit: 'dona',
                    sizeOptions: [],
                    colorOptions: [],
                    variantStocks: [],
                    allowPieceSale: false,
                    pieceUnit: 'kg',
                    pieceQtyPerBase: 0,
                    piecePrice: 0,
                  ),
            );

      if (quantity <= 0) {
        setModalState(() {
          errorText = 'Vazvrat sonini kiriting';
        });
        return;
      }
      if (item.variantLabel.trim().isEmpty &&
          fallbackVariants.isNotEmpty &&
          selectedVariant == null) {
        setModalState(() {
          errorText = 'Avval rangni tanlang';
        });
        return;
      }
      if (quantity - maxQty > 0.0001) {
        setModalState(() {
          errorText = 'Maksimal vazvrat: ${_formatQty(maxQty)} ${item.unit}';
        });
        return;
      }

      setModalState(() {
        submittingItemId = itemKey;
        errorText = '';
      });

      try {
        final resolvedVariantSize = item.variantSize.isNotEmpty
            ? item.variantSize
            : (selectedVariant?.size ?? '');
        final resolvedVariantColor = item.variantColor.isNotEmpty
            ? item.variantColor
            : (selectedVariant?.color ?? '');
        final response = await ref
            .read(salesRepositoryProvider)
            .returnSale(
              token: token,
              saleId: sale.id,
              payload: {
                'paymentType': selectedReturnPaymentType,
                'items': [
                  {
                    'productId': item.productId,
                    'quantity': quantity,
                    'variantSize': resolvedVariantSize,
                    'variantColor': resolvedVariantColor,
                  },
                ],
              },
            );

        final rawSale = response['sale'];
        SaleRecord? updatedSale;
        if (rawSale is Map<String, dynamic>) {
          updatedSale = SaleRecord.fromJson(rawSale);
        } else if (rawSale is Map) {
          updatedSale = SaleRecord.fromJson(Map<String, dynamic>.from(rawSale));
        }

        if (updatedSale != null) {
          result = _ReturnResult(
            updatedSale: updatedSale,
            receipt: _ReceiptSaleData(
              receiptNumber: 'RET-${sale.receiptNumber}',
              shiftNumber: sale.shiftNumber,
              createdAt: DateTime.now(),
              cashierUsername: sale.cashierUsername,
              paymentType: selectedReturnPaymentType,
              paymentDetails: _receiptPaymentDetailsFromValues(
                cash: selectedReturnPaymentType == 'cash'
                    ? item.unitPrice * quantity
                    : 0,
                card: selectedReturnPaymentType == 'card'
                    ? item.unitPrice * quantity
                    : 0,
                click: selectedReturnPaymentType == 'click'
                    ? item.unitPrice * quantity
                    : 0,
              ),
              customerName: sale.customerName,
              totalAmount: item.unitPrice * quantity,
              items: [
                _ReceiptSaleItemData(
                  productName: item.productName,
                  productCode: item.productCode,
                  variantLabel: _composeVariantLabel(
                    resolvedVariantSize,
                    resolvedVariantColor,
                  ),
                  quantity: quantity,
                  unitPrice: item.unitPrice,
                  lineTotal: item.unitPrice * quantity,
                ),
              ],
            ),
          );
        }

        if (context.mounted) {
          Navigator.of(context).pop();
        }
      } catch (error) {
        setModalState(() {
          errorText = ref
              .read(authControllerProvider.notifier)
              .formatError(error);
          submittingItemId = '';
        });
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setModalState) {
            final visibleItems = groupedItems.where((item) {
              final haystack = [
                item.productName,
                item.productModel,
                item.categoryName,
                item.barcode,
                item.variantSize,
                item.variantColor,
              ].join(' ').toLowerCase();
              return query.isEmpty || haystack.contains(query);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 90,
                vertical: 40,
              ),
              backgroundColor: const Color(0xFF102245),
              child: Container(
                width: 980,
                height: 680,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Vazvrat qilish',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chek: ${sale.id}   Kassir: ${sale.cashierUsername}   Sana: ${DateFormat('dd.MM.yyyy HH:mm').format(sale.createdAt ?? DateTime.now())}',
                      style: const TextStyle(
                        color: Color(0xFFD4E6FF),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _WhiteTile(
                      child: Row(
                        children: [
                          _MiniKeyboardButton(
                            onTap: () async {
                              await _openVirtualKeyboard(
                                controller: searchController,
                                title: 'Vazvrat mahsulot qidirish',
                                onSubmitted: (value) {
                                  setModalState(() {
                                    query = value.trim().toLowerCase();
                                  });
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.search_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              focusNode: searchFocusNode,
                              autofocus: true,
                              onChanged: (value) {
                                setModalState(() {
                                  query = value.trim().toLowerCase();
                                });
                              },
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText:
                                    'Mahsulot nomi yoki shtix bilan qidiring, shu yerda scan ham qiling...',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (errorText.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE7E7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          errorText,
                          style: const TextStyle(
                            color: Color(0xFFA12A2A),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF476695),
                            width: 1.2,
                          ),
                        ),
                        child: visibleItems.isEmpty
                            ? const Center(
                                child: Text(
                                  'Vazvrat uchun mahsulot topilmadi',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF49668E),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.all(12),
                                itemCount: visibleItems.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final item = visibleItems[index];
                                  final itemKey =
                                      '${item.productId}:${item.variantSize}:${item.variantColor}:${item.unitPrice}';
                                  final controller =
                                      quantityControllers[itemKey]!;
                                  final disabled = item.isFullyReturned;
                                  final isSubmitting =
                                      submittingItemId == itemKey;
                                  final fallbackVariants =
                                      item.variantLabel.trim().isNotEmpty
                                      ? const <ProductVariantRecord>[]
                                      : _buildSelectableVariants(
                                          productByBarcode[item.barcode] ??
                                              const ProductRecord(
                                                id: '',
                                                name: '',
                                                model: '',
                                                barcode: '',
                                                productCode: '0000',
                                                gender: '',
                                                category: ProductCategoryRef(
                                                  id: '',
                                                  name: '',
                                                ),
                                                supplier: ProductSupplierRef(
                                                  id: '',
                                                  name: '',
                                                  phone: '',
                                                  address: '',
                                                ),
                                                purchasePrice: 0,
                                                priceCurrency: 'uzs',
                                                usdRateUsed: 0,
                                                totalPurchaseCost: 0,
                                                retailPrice: 0,
                                                wholesalePrice: 0,
                                                paymentType: 'naqd',
                                                paidAmount: 0,
                                                debtAmount: 0,
                                                quantity: 0,
                                                unit: 'dona',
                                                sizeOptions: [],
                                                colorOptions: [],
                                                variantStocks: [],
                                                allowPieceSale: false,
                                                pieceUnit: 'kg',
                                                pieceQtyPerBase: 0,
                                                piecePrice: 0,
                                              ),
                                        );
                                  final selectedVariant =
                                      variantSelections[itemKey];

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: disabled
                                            ? const Color(0xFFE0B7B7)
                                            : const Color(0xFFD0DAEA),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    item.productName,
                                                    style: const TextStyle(
                                                      fontSize: 17,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Color(0xFF132745),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  if (item.variantLabel
                                                      .trim()
                                                      .isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFE7F1FF,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                999,
                                                              ),
                                                          border: Border.all(
                                                            color: const Color(
                                                              0xFFB8D3F4,
                                                            ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          'Rangi: ${item.variantLabel}',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                                color: Color(
                                                                  0xFF1B3F6F,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  if (item.variantLabel
                                                          .trim()
                                                          .isEmpty &&
                                                      fallbackVariants
                                                          .isNotEmpty)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'Rangni tanlang',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: Color(
                                                                0xFF345A87,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Wrap(
                                                            spacing: 8,
                                                            runSpacing: 8,
                                                            children: [
                                                              for (final variant
                                                                  in fallbackVariants)
                                                                _ReturnVariantChip(
                                                                  label:
                                                                      _variantDisplayLabel(
                                                                        variant,
                                                                      ),
                                                                  selected:
                                                                      selectedVariant ==
                                                                      variant,
                                                                  onTap: () {
                                                                    setModalState(() {
                                                                      variantSelections[itemKey] =
                                                                          variant;
                                                                    });
                                                                  },
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: [
                                                      if (item
                                                          .barcode
                                                          .isNotEmpty)
                                                        _ProductInfoChip(
                                                          label: 'Shtix',
                                                          value: item.barcode,
                                                        ),
                                                      _ProductInfoChip(
                                                        label: 'Sotilgan',
                                                        value:
                                                            '${_formatQty(item.quantity)} ${item.unit}',
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Qaytgan',
                                                        value:
                                                            '${_formatQty(item.returnedQuantity)} ${item.unit}',
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Qolgan',
                                                        value:
                                                            '${_formatQty(item.availableQuantity)} ${item.unit}',
                                                      ),
                                                      _ProductInfoChip(
                                                        label: 'Narxi',
                                                        value:
                                                            '${_formatMoney(item.unitPrice)} so‘m',
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            SizedBox(
                                              width: 240,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  _DialogInputField(
                                                    label: 'Vazvrat soni',
                                                    controller: controller,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    onKeyboardTap: () async {
                                                      await _openVirtualKeyboard(
                                                        controller: controller,
                                                        title:
                                                            'Vazvrat sonini kiriting',
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                      );
                                                      setModalState(() {});
                                                    },
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          10,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFFFF7F0,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                      border: Border.all(
                                                        color: const Color(
                                                          0xFFFFC894,
                                                        ),
                                                      ),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        const Text(
                                                          'Pulni qaytarish turi',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                              0xFF8A4A12,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            for (final option in const [
                                                              (
                                                                'cash',
                                                                'Naqd',
                                                                Icons
                                                                    .payments_rounded,
                                                              ),
                                                              (
                                                                'card',
                                                                'Karta',
                                                                Icons
                                                                    .credit_card_rounded,
                                                              ),
                                                              (
                                                                'click',
                                                                'Click',
                                                                Icons
                                                                    .touch_app_rounded,
                                                              ),
                                                            ])
                                                              _ReturnPaymentOption(
                                                                label:
                                                                    option.$2,
                                                                icon: option.$3,
                                                                selected:
                                                                    selectedReturnPaymentType ==
                                                                    option.$1,
                                                                onTap: () {
                                                                  setModalState(() {
                                                                    selectedReturnPaymentType =
                                                                        option
                                                                            .$1;
                                                                  });
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  SizedBox(
                                                    height: 48,
                                                    child: _PrimaryActionBox(
                                                      label: disabled
                                                          ? 'VAZVRAT QILINGAN'
                                                          : isSubmitting
                                                          ? 'YUBORILMOQDA'
                                                          : 'VAZVRAT',
                                                      icon: Icons.undo_rounded,
                                                      onTap:
                                                          disabled ||
                                                              isSubmitting
                                                          ? null
                                                          : () => processReturn(
                                                              setModalState,
                                                              item,
                                                            ),
                                                      enabled:
                                                          !disabled &&
                                                          !isSubmitting,
                                                    ),
                                                  ),
                                                ],
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
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    for (final controller in quantityControllers.values) {
      controller.dispose();
    }
    searchController.dispose();
    searchFocusNode.dispose();
    return result;
  }

  Future<void> _showSalesHistoryDialog() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty || _isSubmittingSale) return;

    setState(() {
      _isSubmittingSale = true;
    });

    try {
      final today = DateTime.now();
      final todayLabel = DateFormat('yyyy-MM-dd').format(today);
      final results = await Future.wait<dynamic>([
        ref
            .read(salesRepositoryProvider)
            .fetchSales(
              token: session.token,
              period: '',
              from: todayLabel,
              to: todayLabel,
            ),
        ref.read(settingsRepositoryProvider).fetchSettings(session.token),
      ]);
      if (!mounted) return;

      final history = results[0] as SalesHistoryRecord;
      final settings = results[1] as AppSettingsRecord;
      final sales = [...history.sales]
        ..sort(
          (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
            a.createdAt ?? DateTime(2000),
          ),
        );

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          String query = '';
          final searchController = TextEditingController();
          final searchFocusNode = FocusNode();
          final filteredSales = ValueNotifier<List<SaleRecord>>(sales);

          void updateFilter(String value) {
            query = value.trim().toLowerCase();
            filteredSales.value = sales.where((sale) {
              final haystack = [
                sale.id,
                sale.receiptNumber,
                sale.cashierUsername,
                sale.paymentType,
                sale.customerName,
                ...sale.items.map((item) => item.productName),
                ...sale.items.map((item) => item.barcode),
                ...sale.items.map((item) => item.productCode),
              ].join(' ').toLowerCase();
              return query.isEmpty || haystack.contains(query);
            }).toList();
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(20),
            backgroundColor: const Color(0xFF102245),
            child: Container(
              width: 980,
              height: 640,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Sotuv cheklari tarixi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _WhiteTile(
                    child: Row(
                      children: [
                        _MiniKeyboardButton(
                          onTap: () async {
                            await _openVirtualKeyboard(
                              controller: searchController,
                              title: 'Chek qidirish',
                              onSubmitted: updateFilter,
                            );
                            if (searchFocusNode.canRequestFocus) {
                              searchFocusNode.requestFocus();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.search_rounded),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            autofocus: true,
                            onChanged: updateFilter,
                            onSubmitted: updateFilter,
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD0DAEA),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD0DAEA),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF37A2E5),
                                  width: 1.4,
                                ),
                              ),
                              hintText:
                                  'Chek qidirish: barcode scan qiling yoki mahsulot bo‘yicha toping...',
                              hintStyle: const TextStyle(
                                color: Color(0xFF7088B0),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: const TextStyle(
                              color: Color(0xFF132745),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ValueListenableBuilder<List<SaleRecord>>(
                      valueListenable: filteredSales,
                      builder: (context, visibleSales, _) {
                        if (visibleSales.isEmpty) {
                          return const Center(
                            child: Text(
                              'Sotuv topilmadi',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF476695),
                              width: 1.2,
                            ),
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: visibleSales.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final sale = visibleSales[index];
                              final soldAt = sale.createdAt ?? DateTime.now();
                              final itemSummary = sale.items
                                  .map(
                                    (item) =>
                                        '${item.productName} x${item.quantity.toStringAsFixed(item.quantity == item.quantity.roundToDouble() ? 0 : 2)}',
                                  )
                                  .join(', ');
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0xFFD0DAEA),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Chek № ${sale.receiptNumber}   ${DateFormat('dd.MM.yyyy HH:mm').format(soldAt)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: Color(0xFF132745),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            itemSummary.isEmpty
                                                ? 'Mahsulot yo\'q'
                                                : itemSummary,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF25466E),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Kassir: ${sale.cashierUsername}   To\'lov: ${_paymentTypeLabel(sale.paymentType)}   Jami: ${_formatMoney(sale.totalAmount)}',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF5A7195),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      width: 160,
                                      child: _ActionBox(
                                        label: 'QAYTA CHEK',
                                        icon: Icons.print_rounded,
                                        onTap: () async {
                                          Navigator.of(dialogContext).pop();
                                          await _printSaleRecordReceipt(
                                            settings: settings,
                                            sale: sale,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authControllerProvider.notifier).formatError(error),
          ),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    } finally {
      _barcodeFocusNode.canRequestFocus = true;
      if (mounted) {
        setState(() {
          _isSubmittingSale = false;
          _keepBarcodeFocus = true;
        });
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  Future<Map<String, dynamic>?> _showMixedPaymentDialog(
    double totalAmount,
  ) async {
    final cashController = TextEditingController();
    final cardController = TextEditingController();
    final clickController = TextEditingController();
    String? errorText;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            String formattedRemainder() {
              final cash = _toDoubleValue(cashController.text);
              final card = _toDoubleValue(cardController.text);
              final click = _toDoubleValue(clickController.text);
              return _formatMoney(totalAmount - cash - card - click);
            }

            void fillRemaining(TextEditingController target) {
              final cash = _toDoubleValue(cashController.text);
              final card = _toDoubleValue(cardController.text);
              final click = _toDoubleValue(clickController.text);
              final occupiedAmount = target == cashController
                  ? card + click
                  : target == cardController
                  ? cash + click
                  : cash + card;
              final value = (totalAmount - occupiedAmount).clamp(
                0,
                totalAmount,
              );
              target.text = _formatMoney(value.toDouble());
              target.selection = TextSelection.collapsed(
                offset: target.text.length,
              );
              setLocalState(() {});
            }

            return Dialog(
              backgroundColor: const Color(0xFF102245),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Aralash to\'lov',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Jami summa: ${_formatMoney(totalAmount)}',
                      style: const TextStyle(
                        color: Color(0xFFBFD4F5),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DialogInputField(
                      label: 'Naqt summa',
                      controller: cashController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocalState(() {}),
                      onKeyboardTap: () async {
                        await _openVirtualKeyboard(
                          controller: cashController,
                          title: 'Naqt summa',
                          keyboardType: TextInputType.number,
                        );
                        setLocalState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DialogInputField(
                            label: 'Karta summa',
                            controller: cardController,
                            keyboardType: TextInputType.number,
                            trailing: _MiniActionIconButton(
                              icon: Icons.radio_button_checked_rounded,
                              onTap: () => fillRemaining(cardController),
                            ),
                            onChanged: (_) => setLocalState(() {}),
                            onKeyboardTap: () async {
                              await _openVirtualKeyboard(
                                controller: cardController,
                                title: 'Karta summa',
                                keyboardType: TextInputType.number,
                              );
                              setLocalState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DialogInputField(
                            label: 'Click summa',
                            controller: clickController,
                            keyboardType: TextInputType.number,
                            trailing: _MiniActionIconButton(
                              icon: Icons.radio_button_checked_rounded,
                              onTap: () => fillRemaining(clickController),
                            ),
                            onChanged: (_) => setLocalState(() {}),
                            onKeyboardTap: () async {
                              await _openVirtualKeyboard(
                                controller: clickController,
                                title: 'Click summa',
                                keyboardType: TextInputType.number,
                              );
                              setLocalState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Qolgan summa: ${formattedRemainder()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFFFB3B3),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionBox(
                            label: 'BEKOR',
                            icon: Icons.close_rounded,
                            onTap: () => Navigator.of(dialogContext).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PrimaryActionBox(
                            label: 'SAQLASH',
                            icon: Icons.check_rounded,
                            onTap: () {
                              final cash = _toDoubleValue(cashController.text);
                              final card = _toDoubleValue(cardController.text);
                              final click = _toDoubleValue(
                                clickController.text,
                              );
                              final paid = cash + card + click;
                              if ((paid - totalAmount).abs() > 0.01) {
                                setLocalState(() {
                                  errorText =
                                      'Naqt + karta + click jami summaga teng bo\'lishi kerak';
                                });
                                return;
                              }
                              Navigator.of(dialogContext).pop({
                                'payments': {
                                  'cash': cash,
                                  'card': card,
                                  'click': click,
                                },
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    cashController.dispose();
    cardController.dispose();
    clickController.dispose();
    return result;
  }

  Future<Map<String, double>?> _showCashPaymentDialog(
    double totalAmount, {
    String paymentType = 'cash',
  }) async {
    String paymentTitle() {
      switch (paymentType) {
        case 'card':
          return 'Karta to\'lov';
        case 'click':
          return 'Click to\'lov';
        default:
          return 'Naqd to\'lov';
      }
    }

    final paidController = TextEditingController(
      text: _formatMoney(totalAmount),
    );
    String? errorText;

    final result = await showDialog<Map<String, double>?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final paid = _toDoubleValue(paidController.text);
            final change = paid - totalAmount;
            final hasEnough = change >= -0.0001;

            return Dialog(
              backgroundColor: const Color(0xFF102245),
              child: Container(
                width: 520,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      paymentTitle(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Jami summa: ${_formatMoney(totalAmount)}',
                      style: const TextStyle(
                        color: Color(0xFFBFD4F5),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DialogInputField(
                      label: 'Mijoz bergan summa',
                      controller: paidController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setLocalState(() {
                        errorText = null;
                      }),
                      onKeyboardTap: () async {
                        await _openVirtualKeyboard(
                          controller: paidController,
                          title: '${paymentTitle()} summasi',
                          keyboardType: TextInputType.number,
                        );
                        setLocalState(() {
                          errorText = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Qaytim: ${_formatMoney(math.max(0, change))}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!hasEnough) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Berilgan summa yetarli emas',
                        style: TextStyle(
                          color: Colors.red.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFFFB3B3),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: _ActionBox(
                              label: 'BEKOR',
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: _PrimaryActionBox(
                              label: 'TO\'LOV QILISH',
                              icon: Icons.check_rounded,
                              onTap: () {
                                final received = _toDoubleValue(
                                  paidController.text,
                                );
                                if (received <= 0) {
                                  setLocalState(() {
                                    errorText = 'Summani kiriting';
                                  });
                                  return;
                                }
                                final nextChange = received - totalAmount;
                                if (nextChange < -0.0001) {
                                  setLocalState(() {
                                    errorText = 'Berilgan summa yetarli emas';
                                  });
                                  return;
                                }
                                Navigator.of(dialogContext).pop({
                                  'cashReceived': received.toDouble(),
                                  'change': math
                                      .max(0.0, nextChange)
                                      .toDouble(),
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    paidController.dispose();
    return result;
  }

  Future<Map<String, dynamic>?> _showDebtCustomerDialog(String token) async {
    final lookedUpCustomers = await ref
        .read(customersRepositoryProvider)
        .lookupCustomers(token: token);
    final existingDebtors =
        lookedUpCustomers.where((customer) => customer.totalDebt > 0).toList()
          ..sort((a, b) => b.totalDebt.compareTo(a.totalDebt));

    CustomerRecord? selectedCustomer;
    final searchController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    bool isExisting = existingDebtors.isNotEmpty;
    String? errorText;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredDebtors = existingDebtors.where((customer) {
              final haystack = [
                customer.fullName,
                customer.phone,
                customer.address,
              ].join(' ').toLowerCase();
              return query.isEmpty || haystack.contains(query);
            }).toList();

            if (isExisting &&
                (selectedCustomer == null ||
                    !filteredDebtors.any(
                      (customer) => customer.id == selectedCustomer?.id,
                    )) &&
                filteredDebtors.isNotEmpty) {
              selectedCustomer = filteredDebtors.first;
            }

            return Dialog(
              backgroundColor: const Color(0xFF102245),
              child: Container(
                width: 620,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Qarzga sotuv',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: _PrimaryActionBox(
                              label: 'ESKI QARZDOR',
                              icon: Icons.person_search_rounded,
                              highlighted: isExisting,
                              onTap: () {
                                setLocalState(() {
                                  isExisting = true;
                                  errorText = null;
                                });
                              },
                              enabled: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: _PrimaryActionBox(
                              label: 'YANGI QARZDOR',
                              icon: Icons.person_add_alt_1_rounded,
                              highlighted: !isExisting,
                              onTap: () {
                                setLocalState(() {
                                  isExisting = false;
                                  errorText = null;
                                });
                              },
                              enabled: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isExisting) ...[
                      if (existingDebtors.isEmpty)
                        const Text(
                          'Eski qarzdor mijoz topilmadi. Yangi qarzdor tanlang.',
                          style: TextStyle(
                            color: Color(0xFFFFD0D0),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      else ...[
                        _DialogInputField(
                          label: 'Qidirish',
                          controller: searchController,
                          onChanged: (_) => setLocalState(() {
                            errorText = null;
                          }),
                          onKeyboardTap: () async {
                            await _openVirtualKeyboard(
                              controller: searchController,
                              title: 'Qarzdor qidirish',
                            );
                            setLocalState(() {
                              errorText = null;
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                        _DialogDropdownField(
                          label: 'Qarzdor mijoz',
                          value: selectedCustomer?.id,
                          items: filteredDebtors
                              .map(
                                (customer) => DropdownMenuItem<String>(
                                  value: customer.id,
                                  child: Text(
                                    '${customer.fullName} | ${customer.phone} | qarz: ${_formatMoney(customer.totalDebt)}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setLocalState(() {
                              selectedCustomer = null;
                              for (final customer in filteredDebtors) {
                                if (customer.id == value) {
                                  selectedCustomer = customer;
                                  break;
                                }
                              }
                            });
                          },
                        ),
                      ],
                    ] else ...[
                      _DialogInputField(
                        label: 'Mijoz ismi',
                        controller: nameController,
                        onKeyboardTap: () => _openVirtualKeyboard(
                          controller: nameController,
                          title: 'Mijoz ismi',
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DialogInputField(
                        label: 'Telefon raqami',
                        controller: phoneController,
                        keyboardType: TextInputType.number,
                        onKeyboardTap: () => _openVirtualKeyboard(
                          controller: phoneController,
                          title: 'Telefon raqami',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DialogInputField(
                        label: 'Manzil',
                        controller: addressController,
                        onKeyboardTap: () => _openVirtualKeyboard(
                          controller: addressController,
                          title: 'Manzil',
                        ),
                      ),
                    ],
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFFFB3B3),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: _PrimaryActionBox(
                              label: 'BEKOR',
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(dialogContext).pop(),
                              enabled: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: _PrimaryActionBox(
                              label: 'SAQLASH',
                              icon: Icons.check_rounded,
                              onTap: () {
                                if (isExisting) {
                                  final customer = selectedCustomer;
                                  if (customer == null) {
                                    setLocalState(() {
                                      errorText = 'Qarzdor mijozni tanlang';
                                    });
                                    return;
                                  }
                                  Navigator.of(dialogContext).pop({
                                    'customer': {
                                      'fullName': customer.fullName,
                                      'phone': customer.phone,
                                      'address': customer.address,
                                    },
                                  });
                                  return;
                                }

                                final fullName = nameController.text.trim();
                                final phone = phoneController.text.trim();
                                final address = addressController.text.trim();
                                if (fullName.isEmpty ||
                                    phone.isEmpty ||
                                    address.isEmpty) {
                                  setLocalState(() {
                                    errorText =
                                        'Yangi qarzdor uchun ism, telefon va manzil kerak';
                                  });
                                  return;
                                }
                                Navigator.of(dialogContext).pop({
                                  'customer': {
                                    'fullName': fullName,
                                    'phone': phone,
                                    'address': address,
                                  },
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    return result;
  }

  Future<bool> _printReceipt({
    required AppSettingsRecord settings,
    required String cashierUsername,
    required Map<String, dynamic> sale,
  }) async {
    final receiptSale = _ReceiptSaleData.fromMap(
      sale,
      fallbackCashierUsername: cashierUsername,
    );
    return _printReceiptDocument(settings: settings, sale: receiptSale);
  }

  Future<bool> _printSaleRecordReceipt({
    required AppSettingsRecord settings,
    required SaleRecord sale,
  }) async {
    final receiptSale = _ReceiptSaleData.fromSaleRecord(sale);
    return _printReceiptDocument(settings: settings, sale: receiptSale);
  }

  Future<bool> _printShiftCloseReport(_ShiftCloseReport report) async {
    const mm = 72 / 25.4;
    final pageHeight = 250.0;
    final pageFormat = PdfPageFormat(
      80 * mm,
      pageHeight * mm,
      marginLeft: 4 * mm,
      marginRight: 4 * mm,
      marginTop: 5 * mm,
      marginBottom: 7 * mm,
    );

    Future<Uint8List> buildPdf(PdfPageFormat format) async {
      final doc = pw.Document();
      final openedAt = report.shift.openedAt?.toLocal();
      final closedAt = report.shift.closedAt?.toLocal() ?? report.generatedAt;
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'SMENA YAKUNIY HISOBOTI',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                _buildShiftPdfLine(
                  'Kassa',
                  'Smena ${report.shift.shiftNumber}',
                ),
                _buildShiftPdfLine('Kassir', report.shift.cashierUsername),
                _buildShiftPdfLine(
                  'Ochildi',
                  openedAt == null
                      ? '-'
                      : DateFormat('dd.MM.yyyy HH:mm:ss').format(openedAt),
                ),
                _buildShiftPdfLine(
                  'Yopildi',
                  DateFormat('dd.MM.yyyy HH:mm:ss').format(closedAt),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(),
                pw.SizedBox(height: 4),
                pw.Text(
                  'SOTUVLAR',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                _buildShiftPdfLine(
                  'Sotuvlar soni',
                  '${report.salesReceiptCount}',
                ),
                _buildShiftPdfLine(
                  'Sotuv pozitsiyasi',
                  '${report.salesLineCount}',
                ),
                _buildShiftPdfLine(
                  'Sotilgan birlik',
                  _formatQty(report.salesUnitCount),
                ),
                _buildShiftPdfLine('Naqd', _formatMoney(report.salesCash)),
                _buildShiftPdfLine('Karta', _formatMoney(report.salesCard)),
                _buildShiftPdfLine('Click', _formatMoney(report.salesClick)),
                if (report.salesDebt > 0.0001)
                  _buildShiftPdfLine('Qarz', _formatMoney(report.salesDebt)),
                _buildShiftPdfLine(
                  'Jami summa',
                  _formatMoney(report.salesTotal),
                  emphasized: true,
                ),
                pw.SizedBox(height: 4),
                pw.Divider(),
                pw.SizedBox(height: 4),
                pw.Text(
                  'QAYTARUVLAR',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                _buildShiftPdfLine(
                  'Qaytaruvlar soni',
                  '${report.returnReceiptCount}',
                ),
                _buildShiftPdfLine(
                  'Qaytaruv pozitsiyasi',
                  '${report.returnLineCount}',
                ),
                _buildShiftPdfLine(
                  'Qaytgan birlik',
                  _formatQty(report.returnUnitCount),
                ),
                _buildShiftPdfLine('Naqd', _formatMoney(report.returnCash)),
                _buildShiftPdfLine('Karta', _formatMoney(report.returnCard)),
                _buildShiftPdfLine('Click', _formatMoney(report.returnClick)),
                _buildShiftPdfLine(
                  'Jami qaytaruv',
                  _formatMoney(report.returnTotal),
                  emphasized: true,
                ),
                pw.SizedBox(height: 4),
                pw.Divider(),
                pw.SizedBox(height: 4),
                pw.Text(
                  'YAKUNIY HOLAT',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                _buildShiftPdfLine('Naqd', _formatMoney(report.netCash)),
                _buildShiftPdfLine('Karta', _formatMoney(report.netCard)),
                _buildShiftPdfLine('Click', _formatMoney(report.netClick)),
                _buildShiftPdfLine(
                  'Yakuniy jami',
                  _formatMoney(report.netTotal),
                  emphasized: true,
                ),
              ],
            );
          },
        ),
      );
      return doc.save();
    }

    var printed = false;
    try {
      final printers = await Printing.listPrinters();
      final Printer? printer = printers.cast<Printer?>().firstWhere(
        (item) => item?.isDefault == true,
        orElse: () => printers.isNotEmpty ? printers.first : null,
      );
      if (printer != null) {
        printed = await Printing.directPrintPdf(
          printer: printer,
          onLayout: buildPdf,
          name: 'shift-report-${report.shift.shiftNumber}',
          format: pageFormat,
          usePrinterSettings: true,
        );
      }
    } catch (_) {
      printed = false;
    }

    if (!printed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Smena hisobotini printerga chop qilib bo\'lmadi. Default printerni tekshiring.',
          ),
          backgroundColor: Color(0xFFB9770E),
        ),
      );
    }

    return printed;
  }

  Future<bool> _printReceiptDocument({
    required AppSettingsRecord settings,
    required _ReceiptSaleData sale,
  }) async {
    const mm = 72 / 25.4;
    final receipt = settings.receipt;
    final receiptFields = receipt.fields;
    final isReturnReceipt = sale.receiptNumber.startsWith('RET-');
    final itemCount = sale.items.length;
    final localCreatedAt = sale.createdAt.toLocal();
    final dateText = DateFormat('dd.MM.yyyy').format(localCreatedAt);
    final timeText = DateFormat('HH:mm').format(localCreatedAt);
    Uint8List logoBytes;
    final dataUrl = receipt.logoUrl.trim();
    if (dataUrl.startsWith('data:image/')) {
      final commaIndex = dataUrl.indexOf(',');
      logoBytes = base64Decode(dataUrl.substring(commaIndex + 1));
    } else {
      logoBytes = await rootBundle
          .load('assets/branding/ataway_receipt_logo.png')
          .then((data) => data.buffer.asUint8List());
    }
    final logoImage = pw.MemoryImage(logoBytes);
    final pageHeight = (160 + (itemCount * 24)).toDouble();
    final pageFormat = PdfPageFormat(
      80 * mm,
      pageHeight * mm,
      marginLeft: 4 * mm,
      marginRight: 4 * mm,
      marginTop: 5 * mm,
      marginBottom: 8 * mm,
    );

    Future<Uint8List> buildPdf(PdfPageFormat format) async {
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (receiptFields.showLogo) pw.SizedBox(height: 3),
                if (receiptFields.showLogo)
                  pw.Center(
                    child: pw.Image(
                      logoImage,
                      width: 58 * mm,
                      fit: pw.BoxFit.contain,
                    ),
                  ),
                if (receiptFields.showLogo) pw.SizedBox(height: 6),
                pw.SizedBox(height: 5),
                if (isReturnReceipt)
                  pw.Text(
                    'Amal: Vazvrat',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                if (isReturnReceipt) pw.SizedBox(height: 3),
                if (receiptFields.showReceiptNumber)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Chek raqami:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        sale.receiptNumber,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showDate)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Sana:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        dateText,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showTime)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Vaqt:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        timeText,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showType)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Amal:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        isReturnReceipt ? 'vazvrat' : 'sotuv',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showShift && sale.shiftNumber > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Smena:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        '${sale.shiftNumber}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showCashier)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Kassir:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        sale.cashierUsername,
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (receiptFields.showPaymentType)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'To\'lov:',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _paymentTypeLabel(sale.paymentType),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (sale.paymentDetails.isNotEmpty)
                  ...sale.paymentDetails.map(
                    (detail) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          detail.label,
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          _formatMoney(detail.amount),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (receiptFields.showCustomer && sale.customerName.isNotEmpty)
                  pw.Text(
                    'Mijoz: ${sale.customerName}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                pw.SizedBox(height: 6),
                pw.Text(
                  '----------------------------------------',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (receiptFields.showItemsTable)
                  ...sale.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final qtyText = item.quantity.toStringAsFixed(
                      item.quantity == item.quantity.roundToDouble() ? 0 : 2,
                    );
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '${index + 1}. ${item.productName}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '[${item.productCode}]',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                          if (item.variantLabel.isNotEmpty)
                            pw.Text(
                              item.variantLabel,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                '$qtyText x ${_formatMoney(item.unitPrice)}',
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                              pw.Text(
                                '= ${_formatMoney(item.lineTotal)}',
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                pw.Text(
                  '----------------------------------------',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (receiptFields.showTotal) ...[
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Jami summa',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _formatMoney(sale.totalAmount),
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
                pw.Text(
                  '----------------------------------------',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (receiptFields.showContactLine &&
                    receipt.contactLine.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    receipt.contactLine,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                if (receiptFields.showLegalText &&
                    receipt.legalText.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 5),
                  pw.Text(
                    receipt.legalText.trim(),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
                if (receiptFields.showFooter) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    receipt.footer.isEmpty
                        ? 'XARIDINGIZ UCHUN RAHMAT'
                        : receipt.footer,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
                if (receipt.phoneNumber.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Tel: ${receipt.phoneNumber}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );
      return doc.save();
    }

    var printed = false;
    try {
      final printers = await Printing.listPrinters();
      final Printer? printer = printers.cast<Printer?>().firstWhere(
        (item) => item?.isDefault == true,
        orElse: () => printers.isNotEmpty ? printers.first : null,
      );
      if (printer != null) {
        printed = await Printing.directPrintPdf(
          printer: printer,
          onLayout: buildPdf,
          name: 'receipt-${sale.createdAt.millisecondsSinceEpoch}',
          format: pageFormat,
          usePrinterSettings: true,
        );
      }
    } catch (_) {
      printed = false;
    }

    if (!printed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Printerga to‘g‘ridan chop bo‘lmadi. Default printerni tekshiring.',
          ),
          backgroundColor: Color(0xFFB9770E),
        ),
      );
    }

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _barcodeFocusNode.requestFocus();
      });
    }

    return printed;
  }

  Future<void> _showReceiptPreviewDialog({
    required AppSettingsRecord settings,
    required _ReceiptSaleData sale,
    String dialogTitle = 'Chek tayyor',
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final receipt = settings.receipt;
        final fields = receipt.fields;
        final isReturnReceipt = dialogTitle.toLowerCase().contains('vazvrat');
        final localCreatedAt = sale.createdAt.toLocal();
        final dateText = DateFormat('dd.MM.yyyy').format(localCreatedAt);
        final timeText = DateFormat('HH:mm').format(localCreatedAt);
        Uint8List? logoBytes;
        final logoUrl = receipt.logoUrl.trim();
        if (logoUrl.startsWith('data:image/')) {
          final commaIndex = logoUrl.indexOf(',');
          if (commaIndex != -1) {
            logoBytes = base64Decode(logoUrl.substring(commaIndex + 1));
          }
        }
        return Dialog(
          backgroundColor: const Color(0xFF102245),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dialogTitle,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 320,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Color(0xFF17284B),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (fields.showLogo && receipt.logoUrl.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          if (logoBytes != null)
                            Image.memory(
                              logoBytes,
                              width: 300,
                              height: 150,
                              fit: BoxFit.contain,
                            )
                          else if (logoUrl.startsWith('http'))
                            Image.network(
                              logoUrl,
                              width: 300,
                              height: 150,
                              fit: BoxFit.contain,
                            )
                          else
                            Image.asset(
                              'assets/branding/ataway_receipt_logo.png',
                              width: 300,
                              height: 150,
                              fit: BoxFit.contain,
                            ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 10),
                        if (isReturnReceipt)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              'Amal: Vazvrat',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (fields.showReceiptNumber)
                          _receiptMetaRow('Chek raqami', sale.receiptNumber),
                        if (fields.showDate) _receiptMetaRow('Sana', dateText),
                        if (fields.showTime) _receiptMetaRow('Vaqt', timeText),
                        if (fields.showType)
                          _receiptMetaRow(
                            'Amal',
                            isReturnReceipt ? 'vazvrat' : 'sotuv',
                          ),
                        if (fields.showShift && sale.shiftNumber > 0)
                          _receiptMetaRow('Smena', '${sale.shiftNumber}'),
                        if (fields.showCashier)
                          _receiptMetaRow('Kassir', sale.cashierUsername),
                        if (fields.showPaymentType)
                          _receiptMetaRow(
                            'To\'lov',
                            _paymentTypeLabel(sale.paymentType),
                          ),
                        if (sale.paymentDetails.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ...sale.paymentDetails.map(
                            (detail) => Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  detail.label,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _formatMoney(detail.amount),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          '----------------------------------------',
                          textAlign: TextAlign.center,
                        ),
                        ...sale.items.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${entry.key + 1}. ${entry.value.productName}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '[${entry.value.productCode}]',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (entry.value.variantLabel.isNotEmpty)
                                  Text(
                                    entry.value.variantLabel,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${_formatQty(entry.value.quantity)} x ${_formatMoney(entry.value.unitPrice)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '= ${_formatMoney(entry.value.lineTotal)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '----------------------------------------',
                          textAlign: TextAlign.center,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Jami summa',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              _formatMoney(sale.totalAmount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          '----------------------------------------',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        if (fields.showContactLine &&
                            receipt.contactLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            receipt.contactLine,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (fields.showLegalText &&
                            receipt.legalText.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            receipt.legalText.trim(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (fields.showFooter)
                          Text(
                            receipt.footer.isEmpty
                                ? 'XARIDINGIZ UCHUN RAHMAT'
                                : receipt.footer,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (receipt.phoneNumber.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Tel: ${receipt.phoneNumber}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Yopish'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCashDrawer({bool showSuccessMessage = true}) async {
    try {
      if (Platform.isWindows) {
        await _openCashDrawerLocally();
      } else {
        final session = ref.read(authControllerProvider).valueOrNull;
        if (session == null || session.token.isEmpty) return;
        await ref
            .read(settingsRepositoryProvider)
            .openCashDrawer(token: session.token);
      }

      if (showSuccessMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pul qutisi ochildi'),
            backgroundColor: Color(0xFF1F8F55),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pul qutisi ochilmadi: ${ref.read(authControllerProvider.notifier).formatError(error)}',
          ),
          backgroundColor: const Color(0xFFC0392B),
        ),
      );
    }
  }

  Future<_DailyShiftReport> _loadDailyShiftReport({
    required String token,
    required ShiftRecord shift,
  }) async {
    final history = await ref
        .read(salesRepositoryProvider)
        .fetchSales(
          token: token,
          period: 'all',
          from: '',
          to: '',
          shiftId: shift.id,
        );
    return _DailyShiftReport.fromSales(
      shift: shift,
      sales: history.sales,
      generatedAt: DateTime.now(),
    );
  }

  _ReturnLookupEntry? _findReturnEntry(List<SaleRecord> sales, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final matches = <_ReturnLookupEntry>[];
    for (final sale in sales) {
      if (sale.transactionType != 'sale') continue;
      for (final item in sale.items) {
        if (item.availableQuantity <= 0.0001) continue;
        final haystack = [
          sale.receiptNumber,
          item.productName,
          item.productModel,
          item.categoryName,
          item.barcode,
          item.productCode,
          item.variantSize,
          item.variantColor,
        ].join(' ').toLowerCase();
        if (haystack.contains(normalized)) {
          matches.add(_ReturnLookupEntry(sale: sale, item: item));
        }
      }
    }

    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final aExact =
          a.item.barcode.toLowerCase() == normalized ||
              a.item.productCode.toLowerCase() == normalized ||
              a.sale.receiptNumber.toLowerCase() == normalized
          ? 1
          : 0;
      final bExact =
          b.item.barcode.toLowerCase() == normalized ||
              b.item.productCode.toLowerCase() == normalized ||
              b.sale.receiptNumber.toLowerCase() == normalized
          ? 1
          : 0;
      if (aExact != bExact) return bExact.compareTo(aExact);
      return (b.sale.createdAt ?? DateTime(2000)).compareTo(
        a.sale.createdAt ?? DateTime(2000),
      );
    });
    return matches.first;
  }

  List<String> _availableReturnPaymentTypes(_ReturnLookupEntry? entry) {
    return const ['cash', 'card', 'click'];
  }

  String _defaultReturnPaymentType(_ReturnLookupEntry? entry) {
    return _availableReturnPaymentTypes(entry).first;
  }

  _ReceiptSaleData _buildReturnReceiptData({
    required _ReturnLookupEntry entry,
    required double quantity,
    required String paymentType,
  }) {
    return _ReceiptSaleData(
      receiptNumber: 'RET-${entry.sale.receiptNumber}',
      shiftNumber: entry.sale.shiftNumber,
      createdAt: DateTime.now(),
      cashierUsername: entry.sale.cashierUsername,
      paymentType: paymentType,
      paymentDetails: _receiptPaymentDetailsFromValues(
        cash: paymentType == 'cash' ? entry.item.unitPrice * quantity : 0,
        card: paymentType == 'card' ? entry.item.unitPrice * quantity : 0,
        click: paymentType == 'click' ? entry.item.unitPrice * quantity : 0,
      ),
      customerName: entry.sale.customerName,
      totalAmount: entry.item.unitPrice * quantity,
      items: [
        _ReceiptSaleItemData(
          productName: entry.item.productName,
          productCode: entry.item.productCode,
          variantLabel: [
            if (entry.item.variantSize.isNotEmpty) entry.item.variantSize,
            if (entry.item.variantColor.isNotEmpty) entry.item.variantColor,
          ].join(' / '),
          quantity: quantity,
          unitPrice: entry.item.unitPrice,
          lineTotal: entry.item.unitPrice * quantity,
        ),
      ],
    );
  }

  Future<void> _showDailyReport() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;
    final future = Future.wait<dynamic>([
      ref
          .read(shiftsRepositoryProvider)
          .fetchShifts(
            token: session.token,
            period: 'all',
            from: '',
            to: '',
            cashierUsername: session.user.username,
          ),
      ref
          .read(salesRepositoryProvider)
          .fetchSales(
            token: session.token,
            period: 'all',
            from: '',
            to: '',
            cashierUsername: session.user.username,
          ),
    ]);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return FutureBuilder<List<dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Dialog(
                backgroundColor: Color(0xFF102245),
                child: SizedBox(
                  width: 360,
                  height: 180,
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF37A2E5)),
                  ),
                ),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return Dialog(
                backgroundColor: const Color(0xFF102245),
                child: SizedBox(
                  width: 520,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hisobot yuklanmadi',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          ref
                              .read(authControllerProvider.notifier)
                              .formatError(snapshot.error ?? 'Noma\'lum xato'),
                          style: const TextStyle(
                            color: Color(0xFFBDD0EE),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 140,
                            height: 46,
                            child: _PrimaryActionBox(
                              label: 'YOPISH',
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final shiftsResult = snapshot.data![0] as ShiftsListRecord;
            final salesHistory = snapshot.data![1] as SalesHistoryRecord;
            final shifts = [...shiftsResult.shifts]
              ..sort(
                (a, b) => (b.openedAt ?? DateTime(2000)).compareTo(
                  a.openedAt ?? DateTime(2000),
                ),
              );
            final allSales = [...salesHistory.sales]
              ..sort(
                (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
                  a.createdAt ?? DateTime(2000),
                ),
              );

            ShiftRecord? findShiftById(String id) {
              for (final shift in shifts) {
                if (shift.id == id) return shift;
              }
              return null;
            }

            ShiftRecord buildAggregateShift() {
              DateTime? earliestOpenedAt;
              DateTime? latestClosedAt;
              var totalSalesCount = 0;
              var totalItemsCount = 0.0;
              var totalAmount = 0.0;
              var totalCash = 0.0;
              var totalCard = 0.0;
              var totalClick = 0.0;
              var totalDebt = 0.0;

              for (final shift in shifts) {
                if (shift.openedAt != null &&
                    (earliestOpenedAt == null ||
                        shift.openedAt!.isBefore(earliestOpenedAt))) {
                  earliestOpenedAt = shift.openedAt;
                }
                final candidateClosedAt = shift.closedAt ?? shift.lastSaleAt;
                if (candidateClosedAt != null &&
                    (latestClosedAt == null ||
                        candidateClosedAt.isAfter(latestClosedAt))) {
                  latestClosedAt = candidateClosedAt;
                }
                totalSalesCount += shift.totalSalesCount;
                totalItemsCount += shift.totalItemsCount;
                totalAmount += shift.totalAmount;
                totalCash += shift.totalCash;
                totalCard += shift.totalCard;
                totalClick += shift.totalClick;
                totalDebt += shift.totalDebt;
              }

              return ShiftRecord(
                id: '',
                cashierId: session.user.id,
                cashierUsername: session.user.username,
                shiftNumber: 0,
                status: shifts.any((item) => item.isOpen) ? 'open' : 'closed',
                openedAt: earliestOpenedAt,
                closedAt: latestClosedAt,
                totalSalesCount: totalSalesCount,
                totalItemsCount: totalItemsCount,
                totalAmount: totalAmount,
                totalCash: totalCash,
                totalCard: totalCard,
                totalClick: totalClick,
                totalDebt: totalDebt,
                lastSaleAt: latestClosedAt,
              );
            }

            String formatShiftOption(ShiftRecord shift) {
              final opened = shift.openedAt == null
                  ? '-'
                  : DateFormat('dd.MM HH:mm').format(shift.openedAt!);
              return 'Smena #${shift.shiftNumber} • $opened';
            }

            String selectedShiftId = '';

            return StatefulBuilder(
              builder: (context, setModalState) {
                final selectedShift = findShiftById(selectedShiftId);
                final report = _DailyShiftReport.fromSales(
                  shift: selectedShift ?? buildAggregateShift(),
                  sales: selectedShift == null
                      ? allSales
                      : allSales
                            .where((sale) => sale.shiftId == selectedShift.id)
                            .toList(),
                  generatedAt: DateTime.now(),
                );
                final titleText = selectedShift == null
                    ? 'Kunlik hisobot • ${session.user.username}'
                    : 'Kunlik hisobot • ${session.user.username} • Smena #${selectedShift.shiftNumber}';
                final rangeText = selectedShift == null
                    ? '${_dateTimeLabel(report.shift.openedAt)} - ${DateFormat('dd.MM.yyyy HH:mm').format(report.generatedAt)} • ${shifts.length} smena'
                    : '${_dateTimeLabel(selectedShift.openedAt)} - ${DateFormat('dd.MM.yyyy HH:mm').format(selectedShift.closedAt ?? selectedShift.lastSaleAt ?? report.generatedAt)}';

                return Dialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  backgroundColor: const Color(0xFF102245),
                  child: Container(
                    width: 1180,
                    constraints: const BoxConstraints(maxHeight: 820),
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titleText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 27,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    rangeText,
                                    style: const TextStyle(
                                      color: Color(0xFF9EB6DA),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: 320,
                          child: _DialogDropdownField(
                            label: 'Smena filtri',
                            value: selectedShiftId,
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('Barcha smenalar'),
                              ),
                              ...shifts.map(
                                (shift) => DropdownMenuItem<String>(
                                  value: shift.id,
                                  child: Text(
                                    formatShiftOption(shift),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              setModalState(() {
                                selectedShiftId = value ?? '';
                              });
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _DailyReportStatCard(
                              label: 'Tushum',
                              value: '${_formatMoney(report.netRevenue)} so\'m',
                              icon: Icons.payments_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'Savdolar soni',
                              value: '${report.salesCount}',
                              icon: Icons.shopping_cart_checkout_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'Vazvratlar soni',
                              value: '${report.returnsCount}',
                              icon: Icons.keyboard_return_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'O\'rtacha chek',
                              value:
                                  '${_formatMoney(report.averageCheck)} so\'m',
                              icon: Icons.analytics_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'Naqd',
                              value: '${_formatMoney(report.cashTotal)} so\'m',
                              icon: Icons.payments_outlined,
                            ),
                            _DailyReportStatCard(
                              label: 'Karta',
                              value: '${_formatMoney(report.cardTotal)} so\'m',
                              icon: Icons.credit_card_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'Click',
                              value: '${_formatMoney(report.clickTotal)} so\'m',
                              icon: Icons.touch_app_rounded,
                            ),
                            _DailyReportStatCard(
                              label: 'Sotilgan dona',
                              value: _formatQty(report.netItemQuantity),
                              icon: Icons.inventory_2_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'To\'lovlar tafsiloti',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF1FB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF476695),
                              ),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF37A2E5),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(14),
                                      topRight: Radius.circular(14),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'To\'lov turi',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Savdo',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Vazvrat',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Jami',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    itemBuilder: (context, index) {
                                      final row = report.payments[index];
                                      return Row(
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              row.label,
                                              style: const TextStyle(
                                                color: Color(0xFF1A355B),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              '${_formatMoney(row.salesAmount)} so\'m',
                                              style: const TextStyle(
                                                color: Color(0xFF1A355B),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              '${_formatMoney(row.returnAmount)} so\'m',
                                              style: const TextStyle(
                                                color: Color(0xFFB33939),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              '${_formatMoney(row.totalAmount)} so\'m',
                                              style: const TextStyle(
                                                color: Color(0xFF102245),
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                    separatorBuilder: (context, index) =>
                                        const Divider(
                                          height: 16,
                                          color: Color(0xFFD0DAEA),
                                        ),
                                    itemCount: report.payments.length,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD8E7FB),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(14),
                                      bottomRight: Radius.circular(14),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                        flex: 3,
                                        child: Text(
                                          'JAMI',
                                          style: TextStyle(
                                            color: Color(0xFF0D223F),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          '${_formatMoney(report.totalSalesByPayments)} so\'m',
                                          style: const TextStyle(
                                            color: Color(0xFF0D223F),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          '${_formatMoney(report.totalReturnsByPayments)} so\'m',
                                          style: const TextStyle(
                                            color: Color(0xFFB33939),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          '${_formatMoney(report.totalNetByPayments)} so\'m',
                                          style: const TextStyle(
                                            color: Color(0xFF0D223F),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 180,
                            height: 50,
                            child: _PrimaryActionBox(
                              label: 'YOPISH',
                              icon: Icons.check_rounded,
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showReturnPlaceholderModal() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.token.isEmpty) return;
    if (_currentShift == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Avval smenani boshlang')));
      return;
    }

    setState(() {
      _isSubmittingSale = true;
      _keepBarcodeFocus = false;
    });
    _barcodeFocusNode.unfocus();
    _barcodeFocusNode.canRequestFocus = false;

    try {
      final results = await Future.wait([
        ref
            .read(salesRepositoryProvider)
            .fetchSales(token: session.token, period: 'all', from: '', to: ''),
        ref.read(settingsRepositoryProvider).fetchSettings(session.token),
      ]);

      final sales = (results[0] as SalesHistoryRecord).sales.toList()
        ..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
      final settings = results[1] as AppSettingsRecord;

      if (mounted) {
        setState(() {
          _isSubmittingSale = false;
        });
      }

      await _showReturnCreateDialog(
        token: session.token,
        sales: sales,
        settings: settings,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.read(authControllerProvider.notifier).formatError(error),
            ),
            backgroundColor: const Color(0xFFC0392B),
          ),
        );
      }
    } finally {
      _barcodeFocusNode.canRequestFocus = true;
      if (mounted) {
        setState(() {
          _isSubmittingSale = false;
          _keepBarcodeFocus = true;
        });
        _barcodeFocusNode.requestFocus();
      }
    }
  }

  Future<void> _showReturnCreateDialog({
    required String token,
    required List<SaleRecord> sales,
    required AppSettingsRecord settings,
  }) async {
    final searchController = TextEditingController();
    final quantityController = TextEditingController(text: '1');
    final searchFocusNode = FocusNode();
    var query = '';
    var errorText = '';
    var isSubmitting = false;
    var didRequestFocus = false;
    _ReturnLookupEntry? selectedEntry = _findReturnEntry(sales, query);
    var selectedPaymentType = _defaultReturnPaymentType(selectedEntry);

    Future<void> submitReturn(
      StateSetter setModalState,
      BuildContext dialogContext,
    ) async {
      final entry = selectedEntry;
      if (entry == null) {
        setModalState(() {
          errorText = 'Sotilgan mahsulot topilmadi';
        });
        return;
      }

      final quantity = _toDoubleValue(quantityController.text);
      if (quantity <= 0) {
        setModalState(() {
          errorText = 'Vazvrat sonini kiriting';
        });
        return;
      }

      if (quantity - entry.item.availableQuantity > 0.0001) {
        setModalState(() {
          errorText =
              'Maksimal vazvrat: ${_formatQty(entry.item.availableQuantity)} ${entry.item.unit}';
        });
        return;
      }

      setModalState(() {
        isSubmitting = true;
        errorText = '';
      });

      try {
        final response = await ref
            .read(salesRepositoryProvider)
            .returnSale(
              token: token,
              saleId: entry.sale.id,
              payload: {
                'paymentType': selectedPaymentType,
                'items': [
                  {
                    'productId': entry.item.productId,
                    'quantity': quantity,
                    'variantSize': entry.item.variantSize,
                    'variantColor': entry.item.variantColor,
                  },
                ],
              },
            );

        final rawSale = response['sale'];
        SaleRecord? updatedSale;
        if (rawSale is Map<String, dynamic>) {
          updatedSale = SaleRecord.fromJson(rawSale);
        } else if (rawSale is Map) {
          updatedSale = SaleRecord.fromJson(Map<String, dynamic>.from(rawSale));
        }

        if (updatedSale != null) {
          final index = sales.indexWhere((item) => item.id == updatedSale!.id);
          if (index >= 0) {
            sales[index] = updatedSale;
          } else {
            sales.insert(0, updatedSale);
          }
        }

        final receiptData = _buildReturnReceiptData(
          entry: entry,
          quantity: quantity,
          paymentType: selectedPaymentType,
        );

        await _printReceiptDocument(settings: settings, sale: receiptData);

        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }

        await _showReceiptPreviewDialog(
          settings: settings,
          sale: receiptData,
          dialogTitle: 'Vazvrat cheki tayyor',
        );
      } catch (error) {
        setModalState(() {
          isSubmitting = false;
          errorText = ref
              .read(authControllerProvider.notifier)
              .formatError(error);
        });
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!didRequestFocus) {
              didRequestFocus = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (searchFocusNode.canRequestFocus) {
                  searchFocusNode.requestFocus();
                }
              });
            }

            final entry = selectedEntry;
            final availablePaymentTypes = _availableReturnPaymentTypes(entry);
            final cardWidth =
                MediaQuery.of(context).size.width.clamp(0, 1400) * 0.16;

            Widget paymentTypeButton(String type) {
              IconData icon;
              switch (type) {
                case 'card':
                  icon = Icons.credit_card_rounded;
                  break;
                case 'click':
                  icon = Icons.ads_click_rounded;
                  break;
                case 'debt':
                  icon = Icons.request_page_rounded;
                  break;
                default:
                  icon = Icons.payments_rounded;
              }

              final isSelected = selectedPaymentType == type;
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  setModalState(() {
                    selectedPaymentType = type;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF6D1F)
                        : const Color(0xFFFFF3E8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFFA869)
                          : const Color(0xFFFFC39A),
                      width: 1.4,
                    ),
                    boxShadow: isSelected
                        ? const [
                            BoxShadow(
                              color: Color(0x33FF6D1F),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF8D4817),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _paymentTypeLabel(type),
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF8D4817),
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Dialog(
              backgroundColor: const Color(0xFF102245),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 26,
                vertical: 18,
              ),
              child: Container(
                width: 980,
                constraints: const BoxConstraints(maxHeight: 760),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vazvrat yaratish',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Shtixni oqiting yoki sotilgan mahsulotni qidiring, keyin soni va qaytim turini tanlang.',
                                style: TextStyle(
                                  color: Color(0xFFD4E6FF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(dialogContext).pop(),
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A3F68),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF172C53),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF2C4A7D),
                          width: 1.2,
                        ),
                      ),
                      child: _DialogInputField(
                        label: 'Qidiruv',
                        controller: searchController,
                        focusNode: searchFocusNode,
                        onKeyboardTap: () => _openVirtualKeyboard(
                          controller: searchController,
                          title: 'Vazvrat uchun qidiruv',
                          onSubmitted: (value) {
                            setModalState(() {
                              query = value.trim();
                              selectedEntry = _findReturnEntry(sales, query);
                              final allowed = _availableReturnPaymentTypes(
                                selectedEntry,
                              );
                              if (!allowed.contains(selectedPaymentType)) {
                                selectedPaymentType = allowed.first;
                              }
                              errorText = '';
                            });
                          },
                        ),
                        onChanged: (value) {
                          setModalState(() {
                            query = value.trim();
                            selectedEntry = _findReturnEntry(sales, query);
                            final allowed = _availableReturnPaymentTypes(
                              selectedEntry,
                            );
                            if (!allowed.contains(selectedPaymentType)) {
                              selectedPaymentType = allowed.first;
                            }
                            errorText = '';
                          });
                        },
                        trailing: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF8B4A1D),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FB),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: const Color(0xFFC7D8EE),
                            width: 1.4,
                          ),
                        ),
                        child: entry == null
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 58,
                                      color: Color(0xFF93A9C7),
                                    ),
                                    SizedBox(height: 14),
                                    Text(
                                      'Sotilgan mahsulot topilmadi',
                                      style: TextStyle(
                                        color: Color(0xFF16335D),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Shtix yoki mahsulot nomini kiriting.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFF5F7598),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: const Color(0xFFD6E2F2),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.item.productName,
                                            style: const TextStyle(
                                              color: Color(0xFF15345D),
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          if (entry.item.productModel
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              entry.item.productModel,
                                              style: const TextStyle(
                                                color: Color(0xFF61799A),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 14),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Shtix',
                                                  value: entry.item.barcode,
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Chek',
                                                  value:
                                                      entry.sale.id.length > 12
                                                      ? entry.sale.id.substring(
                                                          0,
                                                          12,
                                                        )
                                                      : entry.sale.id,
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Sana',
                                                  value: _dateTimeLabel(
                                                    entry.sale.createdAt,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Sotilgan',
                                                  value:
                                                      '${_formatQty(entry.item.quantity)} ${entry.item.unit}',
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Qaytgan',
                                                  value:
                                                      '${_formatQty(entry.item.returnedQuantity)} ${entry.item.unit}',
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Qolgan',
                                                  value:
                                                      '${_formatQty(entry.item.availableQuantity)} ${entry.item.unit}',
                                                ),
                                              ),
                                              SizedBox(
                                                width: cardWidth.toDouble(),
                                                child: _ProductInfoChip(
                                                  label: 'Narx',
                                                  value:
                                                      '${_formatMoney(entry.item.unitPrice)} so\'m',
                                                ),
                                              ),
                                              if (entry.item.variantSize
                                                  .trim()
                                                  .isNotEmpty)
                                                SizedBox(
                                                  width: cardWidth.toDouble(),
                                                  child: _ProductInfoChip(
                                                    label: 'Razmer',
                                                    value:
                                                        entry.item.variantSize,
                                                  ),
                                                ),
                                              if (entry.item.variantColor
                                                  .trim()
                                                  .isNotEmpty)
                                                SizedBox(
                                                  width: cardWidth.toDouble(),
                                                  child: _ProductInfoChip(
                                                    label: 'Rang',
                                                    value:
                                                        entry.item.variantColor,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: const Color(0xFFD6E2F2),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: _DialogInputField(
                                              label: 'Vazvrat soni',
                                              controller: quantityController,
                                              keyboardType:
                                                  TextInputType.number,
                                              onKeyboardTap: () =>
                                                  _openVirtualKeyboard(
                                                    controller:
                                                        quantityController,
                                                    title: 'Vazvrat soni',
                                                    keyboardType:
                                                        TextInputType.number,
                                                    onSubmitted: (_) {
                                                      setModalState(() {
                                                        errorText = '';
                                                      });
                                                    },
                                                  ),
                                              onChanged: (_) {
                                                setModalState(() {
                                                  errorText = '';
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(22),
                                              border: Border.all(
                                                color: const Color(0xFFD6E2F2),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Pulni qaytarish turi',
                                                  style: TextStyle(
                                                    color: Color(0xFF7B461A),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                Wrap(
                                                  spacing: 10,
                                                  runSpacing: 10,
                                                  children:
                                                      availablePaymentTypes
                                                          .map(
                                                            paymentTypeButton,
                                                          )
                                                          .toList(),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    if (errorText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText,
                        style: const TextStyle(
                          color: Color(0xFFFF8E8E),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: _ActionBox(
                              label: 'YOPISH',
                              icon: Icons.close_rounded,
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: _PrimaryActionBox(
                              label: isSubmitting
                                  ? 'SAQLANMOQDA...'
                                  : 'VAZVRAT QILISH',
                              icon: Icons.assignment_return_rounded,
                              onTap: isSubmitting || entry == null
                                  ? null
                                  : () => submitReturn(
                                      setModalState,
                                      dialogContext,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    quantityController.dispose();
    searchFocusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final username = session?.user.username ?? 'kassir';
    final totalAmount = _cartLines.fold<double>(
      0,
      (sum, line) => sum + line.lineTotal,
    );
    final totalItems = _cartLines.fold<int>(
      0,
      (sum, line) => sum + line.quantity,
    );
    final bigDisplayText = _pendingQuantity.isNotEmpty
        ? (_isMultiplyMode ? 'X $_pendingQuantity' : _pendingQuantity)
        : _moneyFormat.format(totalAmount);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidebarWidth = (constraints.maxWidth * 0.215).clamp(
              270.0,
              320.0,
            );

            return Container(
              color: const Color(0xFFFFFCF8),
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _MainSide(
                      now: _now,
                      timeFormat: _timeFormat,
                      dateFormat: _dateFormat,
                      username: username,
                      barcodeController: _barcodeController,
                      barcodeFocusNode: _barcodeFocusNode,
                      onBarcodeSubmitted: _scanBarcode,
                      currentShift: _currentShift,
                      isShiftLoading: _isShiftLoading,
                      isShiftActionLoading: _isShiftActionLoading,
                      onOpenShift: _openShift,
                      onOpenKeyboard: () => _openVirtualKeyboard(
                        controller: _barcodeController,
                        title: 'Shtix yoki mahsulot qidirish',
                        onSubmitted: _scanBarcode,
                      ),
                      onDailyReportTap: _showDailyReport,
                      cartLines: _cartLines,
                      totalAmountText: _moneyFormat.format(totalAmount),
                      totalItemsText: '$totalItems',
                      bigDisplayText: bigDisplayText,
                      isSearching: _isSearching,
                      selectedLineIndex: _selectedLineIndex,
                      onSelectLine: _selectCartLine,
                      onSelectVariant: _selectVariantAt,
                      onToggleWholesale: _toggleWholesaleAt,
                      onRemoveLine: _removeLineAt,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: sidebarWidth,
                    child: _RightSide(
                      onLogout: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      onOpenProductSearch: _openProductPickerModal,
                      onHeldCartsTap: _showHeldCartsDialog,
                      onTopTap: _showTopProductsDialog,
                      onKeyTap: _handleKeypadTap,
                      currentShift: _currentShift,
                      onCloseShift: _closeShift,
                      selectedPaymentType: _selectedPaymentType,
                      onPaymentTap: _selectPaymentType,
                      onPayTap: () => _submitSale(),
                      onSaleWithoutReceiptTap: () =>
                          _submitSale(shouldPrintReceipt: false),
                      onOpenDrawerTap: _openCashDrawer,
                      onReturnTap: _showReturnPlaceholderModal,
                      onReceiptHistoryTap: _showSalesHistoryDialog,
                      isPayEnabled:
                          _cartLines.isNotEmpty &&
                          _currentShift != null &&
                          _selectedPaymentType != null &&
                          !_isSubmittingSale,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MainSide extends StatelessWidget {
  const _MainSide({
    required this.now,
    required this.timeFormat,
    required this.dateFormat,
    required this.username,
    required this.barcodeController,
    required this.barcodeFocusNode,
    required this.onBarcodeSubmitted,
    required this.currentShift,
    required this.isShiftLoading,
    required this.isShiftActionLoading,
    required this.onOpenShift,
    required this.onOpenKeyboard,
    required this.onDailyReportTap,
    required this.cartLines,
    required this.totalAmountText,
    required this.totalItemsText,
    required this.bigDisplayText,
    required this.isSearching,
    required this.selectedLineIndex,
    required this.onSelectLine,
    required this.onSelectVariant,
    required this.onToggleWholesale,
    required this.onRemoveLine,
  });

  final DateTime now;
  final DateFormat timeFormat;
  final DateFormat dateFormat;
  final String username;
  final TextEditingController barcodeController;
  final FocusNode barcodeFocusNode;
  final ValueChanged<String> onBarcodeSubmitted;
  final ShiftRecord? currentShift;
  final bool isShiftLoading;
  final bool isShiftActionLoading;
  final VoidCallback onOpenShift;
  final VoidCallback onOpenKeyboard;
  final VoidCallback onDailyReportTap;
  final List<_CartLine> cartLines;
  final String totalAmountText;
  final String totalItemsText;
  final String bigDisplayText;
  final bool isSearching;
  final int? selectedLineIndex;
  final ValueChanged<int> onSelectLine;
  final ValueChanged<int> onSelectVariant;
  final ValueChanged<int> onToggleWholesale;
  final ValueChanged<int> onRemoveLine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: _BlueTile(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        timeFormat.format(now),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        dateFormat.format(now),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEAF2FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 74,
                child: _BlueTile(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Smena',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEAF2FF),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isShiftLoading
                            ? '...'
                            : (currentShift?.shiftNumber.toString() ?? '-'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 120,
                child: _BlueTile(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.badge_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Kassir',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFEAF2FF),
                                ),
                              ),
                              Text(
                                username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 148,
                child: InkWell(
                  onTap: onDailyReportTap,
                  borderRadius: BorderRadius.circular(10),
                  child: _BlueTile(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.summarize_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'KUNLIK HISOBOT',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 5,
                child: _WhiteTile(
                  child: Row(
                    children: [
                      _MiniKeyboardButton(onTap: onOpenKeyboard),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 16,
                        color: Color(0xFF7088B0),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextField(
                          controller: barcodeController,
                          focusNode: barcodeFocusNode,
                          onSubmitted: onBarcodeSubmitted,
                          textInputAction: TextInputAction.done,
                          readOnly: currentShift == null,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            isDense: true,
                            filled: true,
                            fillColor: Color(0xFFFDFEFF),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            hintText: currentShift == null
                                ? 'Avval smenani boshlang'
                                : 'Shtixni shu yerda scaner qiling',
                            hintStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF7088B0),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            suffixIcon: isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF081225),
                          ),
                          cursorColor: const Color(0xFF081225),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    height: 96,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatBox(
                                  title: 'Summa',
                                  value: totalAmountText,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _StatBox(
                                  title: 'Mahsulot',
                                  value: totalItemsText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: _WhiteTile(
                            child: Center(
                              child: Text(
                                bigDisplayText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 46,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF081225),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7EEF9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF436090),
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 36,
                              child: Row(
                                children: const [
                                  _HeaderCell(label: '№', flex: 1),
                                  _HeaderCell(label: 'Tovar nomi', flex: 6),
                                  _HeaderCell(label: 'Birligi', flex: 2),
                                  _HeaderCell(label: 'Omborda', flex: 2),
                                  _HeaderCell(label: 'Soni', flex: 2),
                                  _HeaderCell(label: 'Narxi', flex: 3),
                                  _HeaderCell(label: 'Jami narxi', flex: 4),
                                  _HeaderCell(label: '', flex: 1),
                                  _HeaderCell(label: '', flex: 1),
                                ],
                              ),
                            ),
                            Expanded(
                              child: cartLines.isEmpty
                                  ? const Center(
                                      child: SizedBox.expand(
                                        child: Opacity(
                                          opacity: 0.22,
                                          child: Image(
                                            image: AssetImage(
                                              'assets/branding/ataway_scan_logo.jpg',
                                            ),
                                            fit: BoxFit.cover,
                                            filterQuality: FilterQuality.high,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      itemCount: cartLines.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(
                                            height: 1,
                                            color: Color(0xFFD0DBEE),
                                          ),
                                      itemBuilder: (context, index) {
                                        final line = cartLines[index];
                                        final isSelected =
                                            selectedLineIndex == index;
                                        final needsVariant =
                                            line.variantLabel.trim().isEmpty &&
                                            (line
                                                    .product
                                                    .sizeOptions
                                                    .isNotEmpty ||
                                                line
                                                    .product
                                                    .colorOptions
                                                    .isNotEmpty ||
                                                line
                                                    .product
                                                    .variantStocks
                                                    .isNotEmpty);
                                        return InkWell(
                                          onTap: () => onSelectLine(index),
                                          child: Container(
                                            color: isSelected
                                                ? const Color(0xFFD8EBFF)
                                                : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 7,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 1,
                                                  child: Text(
                                                    '${index + 1}',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF18304F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 6,
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        line.product.name,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Color(
                                                            0xFF18304F,
                                                          ),
                                                        ),
                                                      ),
                                                      if (line
                                                          .variantLabel
                                                          .isNotEmpty)
                                                        Text(
                                                          line.variantLabel,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color: Color(
                                                                  0xFF315A8C,
                                                                ),
                                                              ),
                                                        ),
                                                      Text(
                                                        line.product.barcode,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Color(
                                                            0xFF6B7FA4,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    line.product.unit,
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF18304F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    _formatMoney(
                                                      line.stockLimit
                                                          .toDouble(),
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFF18304F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    '${line.quantity}',
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Color(0xFF18304F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    _formatMoney(
                                                      line.unitPrice,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: Color(0xFF18304F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 4,
                                                  child: Text(
                                                    _formatMoney(
                                                      line.lineTotal,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: Color(0xFF0F2B4F),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 1,
                                                  child: Center(
                                                    child: InkWell(
                                                      onTap: () {
                                                        if (needsVariant) {
                                                          onSelectVariant(
                                                            index,
                                                          );
                                                        } else {
                                                          onToggleWholesale(
                                                            index,
                                                          );
                                                        }
                                                      },
                                                      child: Container(
                                                        width: 24,
                                                        height: 24,
                                                        decoration: BoxDecoration(
                                                          color: needsVariant
                                                              ? const Color(
                                                                  0xFF1B88DA,
                                                                )
                                                              : line.isWholesale
                                                              ? const Color(
                                                                  0xFFF39C12,
                                                                )
                                                              : const Color(
                                                                  0xFF3D5E93,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Icon(
                                                          needsVariant
                                                              ? Icons
                                                                    .palette_outlined
                                                              : Icons
                                                                    .sell_rounded,
                                                          size: 14,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 1,
                                                  child: Center(
                                                    child: InkWell(
                                                      onTap: () {
                                                        onRemoveLine(index);
                                                      },
                                                      child: Container(
                                                        width: 24,
                                                        height: 24,
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFE74C3C,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.close_rounded,
                                                          size: 15,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
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
                    ),
                  ),
                ],
              ),
              if (currentShift == null)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xA6E7EEF9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            size: 78,
                            color: Color(0xFF081225),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Smena yopilgan.',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF081225),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Ish boshlash uchun smena oching',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF304B72),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: 250,
                            height: 64,
                            child: _PrimaryActionBox(
                              label: isShiftLoading || isShiftActionLoading
                                  ? 'YUKLANMOQDA'
                                  : 'SMENA BOSHLASH',
                              icon: Icons.play_circle_fill_rounded,
                              onTap: isShiftLoading || isShiftActionLoading
                                  ? null
                                  : onOpenShift,
                              enabled: !isShiftLoading && !isShiftActionLoading,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RightSide extends StatelessWidget {
  const _RightSide({
    required this.onLogout,
    required this.onOpenProductSearch,
    required this.onHeldCartsTap,
    required this.onTopTap,
    required this.onKeyTap,
    required this.currentShift,
    required this.onCloseShift,
    required this.selectedPaymentType,
    required this.onPaymentTap,
    required this.onPayTap,
    required this.onSaleWithoutReceiptTap,
    required this.onOpenDrawerTap,
    required this.onReturnTap,
    required this.onReceiptHistoryTap,
    required this.isPayEnabled,
  });

  final VoidCallback onLogout;
  final VoidCallback onOpenProductSearch;
  final VoidCallback onHeldCartsTap;
  final VoidCallback onTopTap;
  final ValueChanged<String> onKeyTap;
  final ShiftRecord? currentShift;
  final VoidCallback onCloseShift;
  final String? selectedPaymentType;
  final ValueChanged<String> onPaymentTap;
  final VoidCallback onPayTap;
  final VoidCallback onSaleWithoutReceiptTap;
  final VoidCallback onOpenDrawerTap;
  final VoidCallback onReturnTap;
  final VoidCallback onReceiptHistoryTap;
  final bool isPayEnabled;

  @override
  Widget build(BuildContext context) {
    const spacing = 2.0;
    const topRowHeight = 34.0;
    const payButtonHeight = 70.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyFont = constraints.maxWidth < 320 ? 9.0 : 10.0;
        const keypadButtonHeight = 48.0;
        const actionButtonHeight = 62.0;

        Widget keyRow(String a, String b, String c) {
          return SizedBox(
            height: keypadButtonHeight,
            child: Row(
              children: [
                Expanded(
                  child: _KeyBox(a, fontSize: keyFont, onTap: onKeyTap),
                ),
                const SizedBox(width: spacing),
                Expanded(
                  child: _KeyBox(b, fontSize: keyFont, onTap: onKeyTap),
                ),
                const SizedBox(width: spacing),
                Expanded(
                  child: _KeyBox(c, fontSize: keyFont, onTap: onKeyTap),
                ),
              ],
            ),
          );
        }

        Widget actionRow(Widget left, Widget right) {
          return SizedBox(
            height: actionButtonHeight,
            child: Row(
              children: [
                Expanded(child: left),
                const SizedBox(width: spacing),
                Expanded(child: right),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: topRowHeight,
              child: Row(
                children: [
                  Expanded(
                    child: _ActionBox(
                      label: '',
                      icon: Icons.add_circle_outline_rounded,
                      onTap: onOpenProductSearch,
                    ),
                  ),
                  SizedBox(width: spacing),
                  Expanded(
                    child: _ActionBox(
                      label: 'NAVBAT',
                      icon: Icons.layers_outlined,
                      onTap: onHeldCartsTap,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: spacing),
            Column(
              children: [
                keyRow('7', '8', '9'),
                const SizedBox(height: spacing),
                keyRow('4', '5', '6'),
                const SizedBox(height: spacing),
                keyRow('1', '2', '3'),
                const SizedBox(height: spacing),
                keyRow('X', '-1', '0'),
              ],
            ),
            const SizedBox(height: spacing),
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  actionRow(
                    _ActionBox(
                      label: 'NAQT',
                      icon: Icons.payments_outlined,
                      isSelected: selectedPaymentType == 'cash',
                      onTap: () => onPaymentTap('cash'),
                    ),
                    _ActionBox(
                      label: 'KARTA',
                      icon: Icons.credit_card_rounded,
                      isSelected: selectedPaymentType == 'card',
                      onTap: () => onPaymentTap('card'),
                    ),
                  ),
                  const SizedBox(height: spacing),
                  actionRow(
                    _ActionBox(
                      label: 'CLICK',
                      icon: Icons.ads_click_rounded,
                      isSelected: selectedPaymentType == 'click',
                      onTap: () => onPaymentTap('click'),
                    ),
                    _ActionBox(
                      label: 'ARALASH',
                      icon: Icons.sync_alt_rounded,
                      isSelected: selectedPaymentType == 'mixed',
                      onTap: () => onPaymentTap('mixed'),
                    ),
                  ),
                  const SizedBox(height: spacing),
                  actionRow(
                    _ActionBox(
                      label: 'QARZ',
                      icon: Icons.request_page_outlined,
                      isSelected: selectedPaymentType == 'debt',
                      onTap: () => onPaymentTap('debt'),
                    ),
                    _ActionBox(
                      label: currentShift == null ? 'SMENA' : 'SMENA YOPISH',
                      icon: currentShift == null
                          ? Icons.lock_outline_rounded
                          : Icons.stop_circle_outlined,
                      onTap: currentShift == null ? null : onCloseShift,
                    ),
                  ),
                  const SizedBox(height: spacing),
                  actionRow(
                    _ActionBox(
                      label: 'VAZVRAT',
                      icon: Icons.undo_rounded,
                      onTap: onReturnTap,
                    ),
                    _ActionBox(
                      label: 'QUTI',
                      icon: Icons.inventory_2_outlined,
                      onTap: onOpenDrawerTap,
                    ),
                  ),
                  const SizedBox(height: spacing),
                  actionRow(
                    _ActionBox(
                      label: 'TOP',
                      icon: Icons.local_fire_department_rounded,
                      onTap: onTopTap,
                    ),
                    _ActionBox(
                      label: 'BEZCHEK',
                      icon: Icons.print_outlined,
                      onTap: isPayEnabled ? onSaleWithoutReceiptTap : null,
                    ),
                  ),
                  const SizedBox(height: spacing),
                  actionRow(
                    _ActionBox(
                      label: 'CHEK',
                      icon: Icons.receipt_long_rounded,
                      onTap: onReceiptHistoryTap,
                    ),
                    _ActionBox(
                      label: 'CHIQISH',
                      icon: Icons.logout_rounded,
                      onTap: onLogout,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: payButtonHeight,
                    child: _PrimaryActionBox(
                      label: "TO'LOV",
                      icon: Icons.payments_rounded,
                      onTap: isPayEnabled ? onPayTap : null,
                      enabled: isPayEnabled,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BlueTile extends StatelessWidget {
  const _BlueTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFB74A16), width: 1.3),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF7A2F), Color(0xFFF15E22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WhiteTile extends StatelessWidget {
  const _WhiteTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB07A), width: 1.3),
      ),
      child: child,
    );
  }
}

class _MiniKeyboardButton extends StatelessWidget {
  const _MiniKeyboardButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0E2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFC595)),
        ),
        child: const Icon(
          Icons.keyboard_alt_rounded,
          size: 18,
          color: Color(0xFFE05A1B),
        ),
      ),
    );
  }
}

class _MiniActionIconButton extends StatelessWidget {
  const _MiniActionIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0E2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFC595)),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFFE05A1B)),
      ),
    );
  }
}

class _ProductInfoChip extends StatelessWidget {
  const _ProductInfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFC56222),
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF72310A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _BlueTile(
            child: Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _WhiteTile(
            child: Center(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF72310A),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogInputField extends StatelessWidget {
  const _DialogInputField({
    required this.label,
    required this.controller,
    this.trailing,
    this.focusNode,
    this.keyboardType,
    this.onChanged,
    this.onKeyboardTap,
  });

  final String label;
  final TextEditingController controller;
  final Widget? trailing;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onKeyboardTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFD7B7),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB07A), width: 1.3),
          ),
          child: Row(
            children: [
              if (onKeyboardTap != null) ...[
                _MiniKeyboardButton(onTap: onKeyboardTap!),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: keyboardType,
                  onChanged: (value) {
                    final isNumeric =
                        keyboardType == TextInputType.number ||
                        keyboardType == TextInputType.phone;
                    if (isNumeric) {
                      final formatted = _formatMoneyInput(value);
                      if (formatted != value) {
                        controller.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      }
                    }
                    onChanged?.call(controller.text);
                  },
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    color: Color(0xFF72310A),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReturnPaymentOption extends StatelessWidget {
  const _ReturnPaymentOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFF6B1A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFF6B1A) : const Color(0xFFFFB47B),
          ),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x29FF6B1A),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : const Color(0xFF9A561A),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : const Color(0xFF8A4A12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnVariantChip extends StatelessWidget {
  const _ReturnVariantChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1B88DA) : const Color(0xFFF2F7FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF1B88DA) : const Color(0xFFBCD4F1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : const Color(0xFF23456F),
          ),
        ),
      ),
    );
  }
}

class _VirtualKeyboardDialog extends StatefulWidget {
  const _VirtualKeyboardDialog({
    required this.title,
    required this.initialValue,
    required this.keyboardType,
  });

  final String title;
  final String initialValue;
  final TextInputType keyboardType;

  @override
  State<_VirtualKeyboardDialog> createState() => _VirtualKeyboardDialogState();
}

class _VirtualKeyboardDialogState extends State<_VirtualKeyboardDialog> {
  late final TextEditingController _controller;
  Offset? _panelOffset;

  bool get _isNumeric =>
      widget.keyboardType == TextInputType.number ||
      widget.keyboardType == TextInputType.phone;

  static const _alphaRows = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', '-', '.'],
  ];

  static const _numericRows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['0', '00', '.'],
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _isNumeric
          ? _formatMoneyInput(widget.initialValue)
          : widget.initialValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _append(String value) {
    setState(() {
      final raw = _isNumeric
          ? _controller.text.replaceAll(' ', '')
          : _controller.text;
      final next = raw + value;
      _controller.text = _isNumeric ? _formatMoneyInput(next) : next;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _backspace() {
    if (_controller.text.isEmpty) return;
    setState(() {
      final raw = _isNumeric
          ? _controller.text.replaceAll(' ', '')
          : _controller.text;
      final next = raw.substring(0, raw.length - 1);
      _controller.text = _isNumeric ? _formatMoneyInput(next) : next;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _isNumeric ? _numericRows : _alphaRows;
    final panelWidth = _isNumeric ? 460.0 : 760.0;
    final panelHeight = _isNumeric ? 520.0 : 580.0;

    return Material(
      color: const Color(0x33000000),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxLeft = (constraints.maxWidth - panelWidth - 16).clamp(
            8.0,
            double.infinity,
          );
          final maxTop = (constraints.maxHeight - panelHeight - 16).clamp(
            8.0,
            double.infinity,
          );
          _panelOffset ??= Offset(
            ((constraints.maxWidth - panelWidth) / 2).clamp(8.0, maxLeft),
            ((constraints.maxHeight - panelHeight) / 2).clamp(8.0, maxTop),
          );
          final safeOffset = Offset(
            _panelOffset!.dx.clamp(8.0, maxLeft),
            _panelOffset!.dy.clamp(8.0, maxTop),
          );
          _panelOffset = safeOffset;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: safeOffset.dx,
                top: safeOffset.dy,
                child: SizedBox(
                  width: panelWidth,
                  height: panelHeight,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF18325E),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF34578B),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _panelOffset = Offset(
                                (_panelOffset!.dx + details.delta.dx).clamp(
                                  8.0,
                                  maxLeft,
                                ),
                                (_panelOffset!.dy + details.delta.dy).clamp(
                                  8.0,
                                  maxTop,
                                ),
                              );
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Color(0xFFA9C4EA),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const Text(
                                  'Surib joylang',
                                  style: TextStyle(
                                    color: Color(0xFFA9C4EA),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _controller.text.isEmpty
                                ? 'Matn kiriting...'
                                : _controller.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _controller.text.isEmpty
                                  ? const Color(0xFF8AA0BF)
                                  : const Color(0xFF10203F),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Column(
                            children: [
                              for (final row in rows) ...[
                                Expanded(
                                  child: Row(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < row.length;
                                        index++
                                      ) ...[
                                        Expanded(
                                          child: _KeyboardKey(
                                            label: row[index],
                                            onTap: () => _append(row[index]),
                                            compact: true,
                                          ),
                                        ),
                                        if (index != row.length - 1)
                                          const SizedBox(width: 10),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (!_isNumeric) ...[
                                SizedBox(
                                  height: 64,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _KeyboardKey(
                                          label: 'Bo‘sh joy',
                                          onTap: () => _append(' '),
                                          compact: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _KeyboardKey(
                                          label: 'Tozalash',
                                          onTap: () {
                                            setState(() {
                                              _controller.clear();
                                            });
                                          },
                                          compact: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _KeyboardKey(
                                          label: 'O‘chirish',
                                          onTap: _backspace,
                                          compact: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ] else
                                SizedBox(
                                  height: 64,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _KeyboardKey(
                                          label: 'Tozalash',
                                          onTap: () {
                                            setState(() {
                                              _controller.clear();
                                            });
                                          },
                                          compact: true,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _KeyboardKey(
                                          label: 'O‘chirish',
                                          onTap: _backspace,
                                          compact: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: _ActionBox(
                                  label: 'BEKOR',
                                  icon: Icons.close_rounded,
                                  onTap: () => Navigator.of(context).pop(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 56,
                                child: _PrimaryActionBox(
                                  label: 'TAYYOR',
                                  icon: Icons.check_rounded,
                                  onTap: () => Navigator.of(
                                    context,
                                  ).pop(_controller.text),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KeyboardKey extends StatelessWidget {
  const _KeyboardKey({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF7A2F), Color(0xFFF15E22)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFB74A16), width: 1.2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 14 : 18,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF72310A),
          ),
        ),
      ),
    );
  }
}

class _DialogDropdownField extends StatelessWidget {
  const _DialogDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFFD7B7),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB07A), width: 1.3),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFFFFFCF8),
              style: const TextStyle(
                color: Color(0xFF72310A),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFF7A2F),
          border: const Border(right: BorderSide(color: Color(0xFFAD4716))),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ActionBox extends StatelessWidget {
  const _ActionBox({
    required this.label,
    this.icon,
    this.onTap,
    this.isSelected = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF9A390C)
                : const Color(0xFFB74A16),
            width: isSelected ? 2 : 1.3,
          ),
          gradient: LinearGradient(
            colors: isSelected
                ? const [Color(0xFFFFC167), Color(0xFFFF8538)]
                : const [Color(0xFFFF7A2F), Color(0xFFF15E22)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: Colors.white),
                      if (label.isNotEmpty) const SizedBox(width: 6),
                    ],
                    if (label.isNotEmpty)
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
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

class _PrimaryActionBox extends StatelessWidget {
  const _PrimaryActionBox({
    required this.label,
    this.icon,
    this.onTap,
    this.enabled = true,
    this.highlighted = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFFFFCF87)
                  : const Color(0xFFB74A16),
              width: highlighted ? 2 : 1.3,
            ),
            gradient: LinearGradient(
              colors: highlighted
                  ? const [Color(0xFFFFA64F), Color(0xFFFF7428)]
                  : const [Color(0xFFFF7A2F), Color(0xFFE65B20)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2A000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyBox extends StatelessWidget {
  const _KeyBox(this.label, {this.fontSize = 16, this.onTap});

  final String label;
  final double fontSize;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(label),
      behavior: HitTestBehavior.opaque,
      child: _BlueTile(
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatMoney(double value) {
  return NumberFormat('#,##0', 'uz').format(value).replaceAll(',', ' ');
}

String _formatMoneyInput(String value) {
  final raw = value.replaceAll(RegExp(r'[^\d.,]'), '');
  if (raw.isEmpty) return '';

  final normalized = raw.replaceAll(',', '.');
  final dotIndex = normalized.indexOf('.');
  final integerPartRaw = dotIndex == -1
      ? normalized
      : normalized.substring(0, dotIndex);
  final fractionPart = dotIndex == -1
      ? ''
      : normalized.substring(dotIndex + 1).replaceAll('.', '');

  final digits = integerPartRaw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return fractionPart.isEmpty ? '' : '0.$fractionPart';
  }

  final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final normalizedDigits = trimmed.isEmpty ? '0' : trimmed;
  final groups = <String>[];
  for (var index = normalizedDigits.length; index > 0; index -= 3) {
    final start = (index - 3).clamp(0, normalizedDigits.length);
    groups.add(normalizedDigits.substring(start, index));
  }
  final formattedInteger = groups.reversed.join(' ');
  return fractionPart.isEmpty
      ? formattedInteger
      : '$formattedInteger.$fractionPart';
}

double _toDoubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  final normalized =
      value?.toString().replaceAll(RegExp(r'[\s,]'), '').trim() ?? '';
  return double.tryParse(normalized) ?? 0;
}

String _composeVariantLabel(String size, String color) {
  final safeSize = size.trim();
  final safeColor = color.trim();
  if (safeSize.isNotEmpty && safeColor.isNotEmpty) {
    return '$safeSize / $safeColor';
  }
  if (safeColor.isNotEmpty) return safeColor;
  if (safeSize.isNotEmpty) return safeSize;
  return '';
}

String _paymentTypeLabel(String value) {
  switch (value) {
    case 'cash':
      return 'Naqd';
    case 'card':
      return 'Karta';
    case 'click':
      return 'Click';
    case 'mixed':
      return 'Aralash';
    case 'debt':
      return 'Qarz';
    default:
      return value;
  }
}

String _dateTimeLabel(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd.MM.yyyy HH:mm').format(value);
}

class _ShiftCloseReport {
  const _ShiftCloseReport({
    required this.shift,
    required this.items,
    required this.generatedAt,
    required this.salesReceiptCount,
    required this.salesLineCount,
    required this.salesUnitCount,
    required this.salesCash,
    required this.salesCard,
    required this.salesClick,
    required this.salesDebt,
    required this.salesTotal,
    required this.returnReceiptCount,
    required this.returnLineCount,
    required this.returnUnitCount,
    required this.returnCash,
    required this.returnCard,
    required this.returnClick,
    required this.returnTotal,
    required this.netCash,
    required this.netCard,
    required this.netClick,
    required this.netTotal,
  });

  final ShiftRecord shift;
  final List<_ShiftCloseReportItem> items;
  final DateTime generatedAt;
  final int salesReceiptCount;
  final int salesLineCount;
  final double salesUnitCount;
  final double salesCash;
  final double salesCard;
  final double salesClick;
  final double salesDebt;
  final double salesTotal;
  final int returnReceiptCount;
  final int returnLineCount;
  final double returnUnitCount;
  final double returnCash;
  final double returnCard;
  final double returnClick;
  final double returnTotal;
  final double netCash;
  final double netCard;
  final double netClick;
  final double netTotal;

  factory _ShiftCloseReport.fromSales({
    required ShiftRecord shift,
    required List<SaleRecord> sales,
  }) {
    final merged = <String, _ShiftCloseReportItem>{};
    var salesReceiptCount = 0;
    var salesLineCount = 0;
    var salesUnitCount = 0.0;
    var salesCash = 0.0;
    var salesCard = 0.0;
    var salesClick = 0.0;
    var salesDebt = 0.0;
    var salesTotal = 0.0;
    var returnReceiptCount = 0;
    var returnLineCount = 0;
    var returnUnitCount = 0.0;
    var returnCash = 0.0;
    var returnCard = 0.0;
    var returnClick = 0.0;
    var returnTotal = 0.0;

    for (final sale in sales) {
      salesReceiptCount += 1;
      salesCash += sale.payments.cash;
      salesCard += sale.payments.card;
      salesClick += sale.payments.click;
      salesDebt += sale.debtAmount;
      salesTotal += sale.totalAmount;
      for (final item in sale.items) {
        salesLineCount += 1;
        salesUnitCount += item.quantity;
        final current = merged[item.productName];
        if (current == null) {
          merged[item.productName] = _ShiftCloseReportItem(
            productName: item.productName,
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: item.lineTotal,
          );
        } else {
          merged[item.productName] = _ShiftCloseReportItem(
            productName: current.productName,
            quantity: current.quantity + item.quantity,
            unitPrice: item.unitPrice,
            lineTotal: current.lineTotal + item.lineTotal,
          );
        }
        if (item.returnedQuantity > 0.0001 || item.returnedTotal > 0.0001) {
          returnLineCount += 1;
          returnUnitCount += item.returnedQuantity;
          returnTotal += item.returnedTotal;
        }
      }
      if (sale.returnedAmount > 0.0001 || sale.returns.isNotEmpty) {
        returnReceiptCount += sale.returns.isNotEmpty ? sale.returns.length : 1;
      }
      returnCash += sale.returnedPayments.cash;
      returnCard += sale.returnedPayments.card;
      returnClick += sale.returnedPayments.click;
      for (final ret in sale.returns) {
        if (ret.totalAmount > 0.0001) {
          returnTotal += 0;
        }
      }
    }

    final items = merged.values.toList()
      ..sort((a, b) => b.lineTotal.compareTo(a.lineTotal));
    final normalizedReturnTotal = returnTotal > 0.0001
        ? returnTotal
        : (returnCash + returnCard + returnClick);
    return _ShiftCloseReport(
      shift: shift,
      items: items,
      generatedAt: DateTime.now(),
      salesReceiptCount: salesReceiptCount,
      salesLineCount: salesLineCount,
      salesUnitCount: salesUnitCount,
      salesCash: salesCash,
      salesCard: salesCard,
      salesClick: salesClick,
      salesDebt: salesDebt,
      salesTotal: salesTotal,
      returnReceiptCount: returnReceiptCount,
      returnLineCount: returnLineCount,
      returnUnitCount: returnUnitCount,
      returnCash: returnCash,
      returnCard: returnCard,
      returnClick: returnClick,
      returnTotal: normalizedReturnTotal,
      netCash: salesCash - returnCash,
      netCard: salesCard - returnCard,
      netClick: salesClick - returnClick,
      netTotal: salesTotal - normalizedReturnTotal,
    );
  }
}

class _ShiftCloseReportItem {
  const _ShiftCloseReportItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;
}

class _ShiftSummaryPill extends StatelessWidget {
  const _ShiftSummaryPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A4475),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF476695)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9CB3D8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyShiftReport {
  const _DailyShiftReport({
    required this.shift,
    required this.generatedAt,
    required this.salesCount,
    required this.returnsCount,
    required this.grossRevenue,
    required this.totalReturnedAmount,
    required this.netRevenue,
    required this.averageCheck,
    required this.netItemQuantity,
    required this.payments,
  });

  final ShiftRecord shift;
  final DateTime generatedAt;
  final int salesCount;
  final int returnsCount;
  final double grossRevenue;
  final double totalReturnedAmount;
  final double netRevenue;
  final double averageCheck;
  final double netItemQuantity;
  final List<_DailyPaymentBreakdown> payments;

  double get totalSalesByPayments =>
      payments.fold<double>(0, (sum, row) => sum + row.salesAmount);

  double get totalReturnsByPayments =>
      payments.fold<double>(0, (sum, row) => sum + row.returnAmount);

  double get totalNetByPayments =>
      payments.fold<double>(0, (sum, row) => sum + row.totalAmount);

  double get cashTotal => _paymentTotal('Naqd');

  double get cardTotal => _paymentTotal('Karta');

  double get clickTotal => _paymentTotal('Click');

  double _paymentTotal(String label) {
    for (final row in payments) {
      if (row.label == label) return row.totalAmount;
    }
    return 0;
  }

  factory _DailyShiftReport.fromSales({
    required ShiftRecord shift,
    required List<SaleRecord> sales,
    required DateTime generatedAt,
  }) {
    var salesCount = 0;
    var returnsCount = 0;
    var grossRevenue = 0.0;
    var totalReturnedAmount = 0.0;
    var netRevenue = 0.0;
    var soldItems = 0.0;
    var returnedItems = 0.0;

    var grossCash = 0.0;
    var grossCard = 0.0;
    var grossClick = 0.0;
    var grossDebt = 0.0;

    var returnCash = 0.0;
    var returnCard = 0.0;
    var returnClick = 0.0;
    var returnDebt = 0.0;

    var netCash = 0.0;
    var netCard = 0.0;
    var netClick = 0.0;
    var netDebt = 0.0;

    for (final sale in sales) {
      if (sale.transactionType != 'sale') continue;

      salesCount += 1;
      netRevenue += sale.totalAmount;
      totalReturnedAmount += sale.returnedAmount;
      grossRevenue += sale.totalAmount + sale.returnedAmount;

      netCash += sale.payments.cash;
      netCard += sale.payments.card;
      netClick += sale.payments.click;

      returnCash += sale.returnedPayments.cash;
      returnCard += sale.returnedPayments.card;
      returnClick += sale.returnedPayments.click;

      grossCash += sale.payments.cash + sale.returnedPayments.cash;
      grossCard += sale.payments.card + sale.returnedPayments.card;
      grossClick += sale.payments.click + sale.returnedPayments.click;

      if (sale.debtAmount > 0) {
        netDebt += sale.debtAmount;
        grossDebt += sale.debtAmount;
      }

      if (sale.returns.isNotEmpty) {
        returnsCount += sale.returns.length;
        for (final ret in sale.returns) {
          if (ret.paymentType == 'debt') {
            returnDebt += ret.totalAmount;
            grossDebt += ret.totalAmount;
          }
        }
      } else if (sale.returnedAmount > 0.0001) {
        returnsCount += 1;
      }

      for (final item in sale.items) {
        soldItems += item.quantity;
        returnedItems += item.returnedQuantity;
      }
    }

    netDebt = math.max(0, grossDebt - returnDebt);

    final rows = <_DailyPaymentBreakdown>[
      _DailyPaymentBreakdown(
        label: 'Naqd',
        salesAmount: grossCash,
        returnAmount: returnCash,
        totalAmount: netCash,
      ),
      _DailyPaymentBreakdown(
        label: 'Karta',
        salesAmount: grossCard,
        returnAmount: returnCard,
        totalAmount: netCard,
      ),
      _DailyPaymentBreakdown(
        label: 'Click',
        salesAmount: grossClick,
        returnAmount: returnClick,
        totalAmount: netClick,
      ),
      _DailyPaymentBreakdown(
        label: 'Qarz',
        salesAmount: grossDebt,
        returnAmount: returnDebt,
        totalAmount: netDebt,
      ),
    ];

    final visibleRows = rows
        .where(
          (row) =>
              row.salesAmount > 0.0001 ||
              row.returnAmount > 0.0001 ||
              row.totalAmount > 0.0001,
        )
        .toList();

    final averageCheck = salesCount == 0 ? 0.0 : netRevenue / salesCount;
    return _DailyShiftReport(
      shift: shift,
      generatedAt: generatedAt,
      salesCount: salesCount,
      returnsCount: returnsCount,
      grossRevenue: grossRevenue,
      totalReturnedAmount: totalReturnedAmount,
      netRevenue: netRevenue,
      averageCheck: averageCheck,
      netItemQuantity: soldItems - returnedItems,
      payments: visibleRows.isEmpty ? rows.take(3).toList() : visibleRows,
    );
  }
}

class _DailyPaymentBreakdown {
  const _DailyPaymentBreakdown({
    required this.label,
    required this.salesAmount,
    required this.returnAmount,
    required this.totalAmount,
  });

  final String label;
  final double salesAmount;
  final double returnAmount;
  final double totalAmount;
}

class _DailyReportStatCard extends StatelessWidget {
  const _DailyReportStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A4475),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF476695)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF37A2E5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF9CB3D8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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

class _ReturnLookupEntry {
  const _ReturnLookupEntry({required this.sale, required this.item});

  final SaleRecord sale;
  final SaleItemRecord item;
}

class _ReturnSaleGroup {
  const _ReturnSaleGroup({
    required this.productId,
    required this.productName,
    required this.productModel,
    required this.categoryName,
    required this.barcode,
    required this.productCode,
    required this.variantSize,
    required this.variantColor,
    required this.unit,
    required this.unitPrice,
    required this.quantity,
    required this.returnedQuantity,
    required this.lineTotal,
    required this.items,
  });

  final String productId;
  final String productName;
  final String productModel;
  final String categoryName;
  final String barcode;
  final String productCode;
  final String variantSize;
  final String variantColor;
  final String unit;
  final double unitPrice;
  final double quantity;
  final double returnedQuantity;
  final double lineTotal;
  final List<SaleItemRecord> items;

  double get availableQuantity => quantity - returnedQuantity;
  bool get isFullyReturned => availableQuantity <= 0.0001;
  String get variantLabel => _composeVariantLabel(variantSize, variantColor);

  static List<_ReturnSaleGroup> aggregate(List<SaleItemRecord> source) {
    final grouped = <String, _ReturnSaleGroup>{};

    for (final item in source) {
      final key =
          '${item.productId}::${item.variantSize}::${item.variantColor}::${item.unitPrice}';
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = _ReturnSaleGroup(
          productId: item.productId,
          productName: item.productName,
          productModel: item.productModel,
          categoryName: item.categoryName,
          barcode: item.barcode,
          productCode: item.productCode,
          variantSize: item.variantSize,
          variantColor: item.variantColor,
          unit: item.unit,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          returnedQuantity: item.returnedQuantity,
          lineTotal: item.lineTotal,
          items: [item],
        );
        continue;
      }

      grouped[key] = _ReturnSaleGroup(
        productId: existing.productId,
        productName: existing.productName,
        productModel: existing.productModel,
        categoryName: existing.categoryName,
        barcode: existing.barcode,
        productCode: existing.productCode,
        variantSize: existing.variantSize,
        variantColor: existing.variantColor,
        unit: existing.unit,
        unitPrice: existing.unitPrice,
        quantity: existing.quantity + item.quantity,
        returnedQuantity: existing.returnedQuantity + item.returnedQuantity,
        lineTotal: existing.lineTotal + item.lineTotal,
        items: [...existing.items, item],
      );
    }

    final results = grouped.values.toList();
    results.sort((a, b) {
      final nameCompare = a.productName.compareTo(b.productName);
      if (nameCompare != 0) return nameCompare;
      final variantCompare = a.variantLabel.compareTo(b.variantLabel);
      if (variantCompare != 0) return variantCompare;
      return a.barcode.compareTo(b.barcode);
    });
    return results;
  }
}

class _ReturnResult {
  const _ReturnResult({required this.updatedSale, required this.receipt});

  final SaleRecord updatedSale;
  final _ReceiptSaleData receipt;
}

class _ReceiptSaleData {
  const _ReceiptSaleData({
    required this.receiptNumber,
    required this.shiftNumber,
    required this.createdAt,
    required this.cashierUsername,
    required this.paymentType,
    required this.paymentDetails,
    required this.customerName,
    required this.totalAmount,
    required this.items,
  });

  final String receiptNumber;
  final int shiftNumber;
  final DateTime createdAt;
  final String cashierUsername;
  final String paymentType;
  final List<_ReceiptPaymentDetail> paymentDetails;
  final String customerName;
  final double totalAmount;
  final List<_ReceiptSaleItemData> items;

  factory _ReceiptSaleData.fromMap(
    Map<String, dynamic> sale, {
    required String fallbackCashierUsername,
  }) {
    final rawItems = (sale['items'] as List?) ?? const [];
    final cashierUsername = sale['cashierUsername']?.toString() ?? '';
    return _ReceiptSaleData(
      receiptNumber: _normalizeReceiptNumberFromMap(sale),
      shiftNumber: (sale['shiftNumber'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(sale['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      cashierUsername: cashierUsername.trim().isNotEmpty
          ? cashierUsername
          : fallbackCashierUsername,
      paymentType: sale['paymentType']?.toString() ?? '',
      paymentDetails: _receiptPaymentDetailsFromMap(
        sale['payments'] is Map<String, dynamic>
            ? sale['payments'] as Map<String, dynamic>
            : sale['payments'] is Map
            ? Map<String, dynamic>.from(sale['payments'] as Map)
            : null,
      ),
      customerName: sale['customerName']?.toString() ?? '',
      totalAmount: _toDoubleValue(sale['totalAmount']),
      items: rawItems
          .map(
            (item) => item is Map
                ? _ReceiptSaleItemData.fromMap(Map<String, dynamic>.from(item))
                : null,
          )
          .whereType<_ReceiptSaleItemData>()
          .toList(),
    );
  }

  factory _ReceiptSaleData.fromSaleRecord(SaleRecord sale) {
    return _ReceiptSaleData(
      receiptNumber: sale.receiptNumber,
      shiftNumber: sale.shiftNumber,
      createdAt: sale.createdAt ?? DateTime.now(),
      cashierUsername: sale.cashierUsername,
      paymentType: sale.paymentType,
      paymentDetails: _receiptPaymentDetailsFromPayments(sale.payments),
      customerName: sale.customerName,
      totalAmount: sale.totalAmount,
      items: sale.items
          .map(
            (item) => _ReceiptSaleItemData(
              productName: item.productName,
              productCode: item.productCode,
              variantLabel: '',
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              lineTotal: item.lineTotal > 0
                  ? item.lineTotal
                  : item.unitPrice * item.quantity,
            ),
          )
          .toList(),
    );
  }
}

class _ReceiptPaymentDetail {
  const _ReceiptPaymentDetail({required this.label, required this.amount});

  final String label;
  final double amount;
}

List<_ReceiptPaymentDetail> _receiptPaymentDetailsFromMap(
  Map<String, dynamic>? payments,
) {
  return _receiptPaymentDetailsFromValues(
    cash: _toDoubleValue(payments?['cash']),
    card: _toDoubleValue(payments?['card']),
    click: _toDoubleValue(payments?['click']),
  );
}

List<_ReceiptPaymentDetail> _receiptPaymentDetailsFromPayments(
  SalePaymentsRecord payments,
) {
  return _receiptPaymentDetailsFromValues(
    cash: payments.cash,
    card: payments.card,
    click: payments.click,
  );
}

List<_ReceiptPaymentDetail> _receiptPaymentDetailsFromValues({
  required double cash,
  required double card,
  required double click,
}) {
  final details = <_ReceiptPaymentDetail>[];
  if (cash > 0.0001) {
    details.add(_ReceiptPaymentDetail(label: 'Naqd', amount: cash));
  }
  if (card > 0.0001) {
    details.add(_ReceiptPaymentDetail(label: 'Karta', amount: card));
  }
  if (click > 0.0001) {
    details.add(_ReceiptPaymentDetail(label: 'Click', amount: click));
  }
  return details;
}

class _ReceiptSaleItemData {
  const _ReceiptSaleItemData({
    required this.productName,
    required this.productCode,
    required this.variantLabel,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final String productCode;
  final String variantLabel;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  factory _ReceiptSaleItemData.fromMap(Map<String, dynamic> item) {
    final quantity = _toDoubleValue(item['quantity']);
    final unitPrice = _toDoubleValue(item['unitPrice']);
    final variantSize = item['variantSize']?.toString().trim() ?? '';
    final variantColor = item['variantColor']?.toString().trim() ?? '';
    return _ReceiptSaleItemData(
      productName: item['productName']?.toString() ?? '',
      productCode: _normalizeReceiptProductCode(
        item['productCode']?.toString(),
        item['productModel']?.toString(),
        item['barcode']?.toString(),
      ),
      variantLabel: _composeVariantLabel(variantSize, variantColor),
      quantity: quantity,
      unitPrice: unitPrice,
      lineTotal: _toDoubleValue(item['lineTotal']) > 0
          ? _toDoubleValue(item['lineTotal'])
          : quantity * unitPrice,
    );
  }
}

class _PieceSaleSelection {
  const _PieceSaleSelection({
    required this.sellAsPiece,
    required this.quantity,
  });

  final bool sellAsPiece;
  final int quantity;
}

String _normalizeReceiptProductCode(String? value, String? model, String? barcode) {
  final direct = (value ?? '').replaceAll(RegExp(r'\D+'), '');
  if (direct.isNotEmpty) {
    final last = direct.length > 4
        ? direct.substring(direct.length - 4)
        : direct;
    return last.padLeft(4, '0');
  }
  final fromModel = (model ?? '').replaceAll(RegExp(r'\D+'), '');
  if (fromModel.isNotEmpty) {
    final last = fromModel.length > 4
        ? fromModel.substring(fromModel.length - 4)
        : fromModel;
    return last.padLeft(4, '0');
  }
  final fallback = (barcode ?? '').replaceAll(RegExp(r'\D+'), '');
  if (fallback.isNotEmpty) {
    final last = fallback.length > 4
        ? fallback.substring(fallback.length - 4)
        : fallback;
    return last.padLeft(4, '0');
  }
  return '0000';
}

String _normalizeReceiptNumberFromMap(Map<String, dynamic> sale) {
  final saleNumber = (sale['saleNumber'] as num?)?.toInt() ?? 0;
  if (saleNumber > 0) {
    return saleNumber.toString().padLeft(6, '0');
  }

  final rawId = sale['id']?.toString().trim().isNotEmpty == true
      ? sale['id'].toString()
      : sale['_id']?.toString() ?? '';
  final digits = rawId.replaceAll(RegExp(r'\D+'), '');
  if (digits.isNotEmpty) {
    final last = digits.length > 6 ? digits.substring(digits.length - 6) : digits;
    return last.padLeft(4, '0');
  }

  if (rawId.isEmpty) return '1000';
  var hash = 0;
  for (final unit in rawId.codeUnits) {
    hash = (hash * 31 + unit) % 900000;
  }
  final number = 1000 + hash;
  return number.toString().padLeft(4, '0');
}

Widget _receiptMetaRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$label:',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _CartLine {
  const _CartLine({
    required this.product,
    required this.quantity,
    this.variantSize = '',
    this.variantColor = '',
    this.stockLimit = 0,
    this.isWholesale = false,
    this.saleUnit = '',
    this.saleMode = 'base',
    this.stockPerUnitInBase = 1,
    this.fixedUnitPrice,
  });

  final ProductRecord product;
  final int quantity;
  final String variantSize;
  final String variantColor;
  final int stockLimit;
  final bool isWholesale;
  final String saleUnit;
  final String saleMode;
  final double stockPerUnitInBase;
  final double? fixedUnitPrice;

  String get variantLabel => _composeVariantLabel(variantSize, variantColor);

  double get unitPrice {
    if (fixedUnitPrice != null && fixedUnitPrice! > 0) {
      return fixedUnitPrice!;
    }
    return isWholesale && product.wholesalePrice > 0
        ? product.wholesalePrice
        : product.retailPrice;
  }

  String get priceType =>
      isWholesale && product.wholesalePrice > 0 ? 'wholesale' : 'retail';

  double get lineTotal => unitPrice * quantity;

  _CartLine copyWith({
    ProductRecord? product,
    int? quantity,
    String? variantSize,
    String? variantColor,
    int? stockLimit,
    bool? isWholesale,
    String? saleUnit,
    String? saleMode,
    double? stockPerUnitInBase,
    double? fixedUnitPrice,
  }) {
    return _CartLine(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      variantSize: variantSize ?? this.variantSize,
      variantColor: variantColor ?? this.variantColor,
      stockLimit: stockLimit ?? this.stockLimit,
      isWholesale: isWholesale ?? this.isWholesale,
      saleUnit: saleUnit ?? this.saleUnit,
      saleMode: saleMode ?? this.saleMode,
      stockPerUnitInBase: stockPerUnitInBase ?? this.stockPerUnitInBase,
      fixedUnitPrice: fixedUnitPrice ?? this.fixedUnitPrice,
    );
  }
}

class _HeldCart {
  _HeldCart({
    required this.label,
    required this.createdAt,
    required this.lines,
    required this.selectedPaymentType,
  }) : id = '${createdAt.microsecondsSinceEpoch}-${lines.length}';

  final String id;
  final String label;
  final DateTime createdAt;
  final List<_CartLine> lines;
  final String? selectedPaymentType;
}
