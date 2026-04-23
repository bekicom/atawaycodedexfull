import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../categories/data/categories_repository.dart';
import '../../categories/domain/category_record.dart';
import '../../products/data/products_repository.dart';
import '../../products/domain/product_record.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/app_settings_record.dart';
import '../../suppliers/data/suppliers_repository.dart';
import '../../suppliers/domain/supplier_record.dart';

const List<String> _productUnits = ['dona', 'kg', 'blok', 'pachka', 'qop', 'razmer'];
const List<String> _paymentTypes = ['naqd', 'qisman', 'qarz'];
const List<String> _productGenders = ['', 'qiz_bola', 'ogil_bola'];
const List<String> _productColors = [
  'Oq',
  'Qora',
  'Kulrang',
  'Ko\'k',
  'To\'q ko\'k',
  'Havorang',
  'Yashil',
  'To\'q yashil',
  'Sariq',
  'Zarg\'aldoq',
  'Qizil',
  'Pushti',
  'Binafsha',
  'Jigarrang',
  'Bej',
  'Krem',
  'Tilla',
  'Kumush',
  'Bordo',
  'Turkuaz',
  'Anorrang',
  'Och yashil',
  'Och ko\'k',
  'Siyohrang',
  'Nilufar',
  'Qaymoqrang',
];

Color _colorForLabel(String label) {
  switch (label) {
    case 'Oq':
      return const Color(0xFFF5F7FA);
    case 'Qora':
      return const Color(0xFF111111);
    case 'Kulrang':
      return const Color(0xFF9CA3AF);
    case 'Ko\'k':
      return const Color(0xFF2563EB);
    case 'To\'q ko\'k':
      return const Color(0xFF1E3A8A);
    case 'Havorang':
      return const Color(0xFF7DD3FC);
    case 'Yashil':
      return const Color(0xFF22C55E);
    case 'To\'q yashil':
      return const Color(0xFF166534);
    case 'Sariq':
      return const Color(0xFFFACC15);
    case 'Zarg\'aldoq':
      return const Color(0xFFF97316);
    case 'Qizil':
      return const Color(0xFFEF4444);
    case 'Pushti':
      return const Color(0xFFF472B6);
    case 'Binafsha':
      return const Color(0xFF8B5CF6);
    case 'Jigarrang':
      return const Color(0xFF92400E);
    case 'Bej':
      return const Color(0xFFD6C6A5);
    case 'Krem':
      return const Color(0xFFFFF3C4);
    case 'Tilla':
      return const Color(0xFFEAB308);
    case 'Kumush':
      return const Color(0xFFD1D5DB);
    case 'Bordo':
      return const Color(0xFF7F1D1D);
    case 'Turkuaz':
      return const Color(0xFF14B8A6);
    case 'Anorrang':
      return const Color(0xFFBE123C);
    case 'Och yashil':
      return const Color(0xFF86EFAC);
    case 'Och ko\'k':
      return const Color(0xFFBFDBFE);
    case 'Siyohrang':
      return const Color(0xFF312E81);
    case 'Nilufar':
      return const Color(0xFFA78BFA);
    case 'Qaymoqrang':
      return const Color(0xFFFDE68A);
    default:
      return const Color(0xFF244A7C);
  }
}

Color _colorTextFor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xFF102244);
}

bool _supportsPieceSale(String unit) => unit == 'qop' || unit == 'pachka';

String _baseUnitLabel(String unit) => unit == 'pachka' ? 'pachka' : 'qop';

String _defaultPieceUnitFor(String unit) => unit == 'pachka' ? 'dona' : 'kg';

List<String> _normalizeSizeInput(String value) {
  final parts = value
      .split(RegExp(r'[\s,;]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty);
  return parts.toSet().toList();
}

String _joinSizeInput(Iterable<String> values) => values.join(' ');

String _genderLabel(String value) {
  switch (value) {
    case 'qiz_bola':
      return 'Qiz bola';
    case 'ogil_bola':
      return 'O\'g\'il bola';
    default:
      return 'Umumiy';
  }
}

class ProductsDirectContent extends ConsumerStatefulWidget {
  const ProductsDirectContent({super.key});

  @override
  ConsumerState<ProductsDirectContent> createState() =>
      _ProductsDirectContentState();
}

class _ProductsDirectContentState extends ConsumerState<ProductsDirectContent> {
  static const int _pageSize = 15;

  late Future<_ProductsBundle> _future;
  bool _saving = false;
  bool _redirecting = false;
  String _search = '';
  String _selectedCategoryId = '';
  String _errorMessage = '';
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProductsBundle> _load() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) throw Exception('Session topilmadi');
    final results = await Future.wait<dynamic>([
      ref.read(productsRepositoryProvider).fetchProducts(token: session.token),
      ref.read(categoriesRepositoryProvider).fetchCategories(session.token),
      ref.read(suppliersRepositoryProvider).fetchSuppliers(session.token),
      ref.read(settingsRepositoryProvider).fetchSettings(session.token),
    ]);
    return _ProductsBundle(
      products: results[0] as List<ProductRecord>,
      categories: results[1] as List<CategoryRecord>,
      suppliers: results[2] as List<SupplierRecord>,
      settings: results[3] as AppSettingsRecord,
    );
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

  String _formatDebt(ProductRecord product, AppSettingsRecord settings) {
    return '${product.paymentType} / ${_formatMoney(product.debtAmount, settings)}';
  }

  String _formatStockNote(ProductRecord product, AppSettingsRecord settings) {
    if (_supportsPieceSale(product.unit) && product.allowPieceSale) {
      return '1 ${_baseUnitLabel(product.unit)} = ${_formatNumber(product.pieceQtyPerBase)} ${product.pieceUnit}, '
          '1 ${product.pieceUnit} = ${_formatMoney(product.piecePrice, settings)}';
    }
    return '-';
  }

  double _toEditablePrice(double uzsAmount, String currency, double rate) {
    if (currency == 'usd' && rate > 0) {
      return uzsAmount / rate;
    }
    return uzsAmount;
  }

  String _generateLocalBarcode() {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final base = now.length > 10 ? now.substring(now.length - 10) : now;
    final suffix = (100 + DateTime.now().microsecond % 900).toString();
    return '$base$suffix';
  }

  Map<String, dynamic> _payloadFromProduct(
    ProductRecord product,
    String barcode,
  ) {
    return <String, dynamic>{
      'name': product.name,
      'model': product.model,
      'barcode': barcode,
      'gender': product.gender,
      'categoryId': product.category.id,
      'supplierId': product.supplier.id,
      'purchasePrice': product.purchasePrice,
      'priceCurrency': product.priceCurrency,
      'retailPrice': product.retailPrice,
      'wholesalePrice': product.wholesalePrice,
      'paymentType': product.paymentType,
      'paidAmount': product.paidAmount,
      'quantity': product.quantity,
      'unit': product.unit,
      'sizeOptions': product.sizeOptions,
      'colorOptions': product.colorOptions,
      'variantStocks': product.variantStocks
          .map(
            (item) => {
              'size': item.size,
              'color': item.color,
              'quantity': item.quantity,
            },
          )
          .toList(),
      'allowPieceSale': product.allowPieceSale,
      'pieceUnit': product.pieceUnit,
      'pieceQtyPerBase': product.pieceQtyPerBase,
      'piecePrice': product.piecePrice,
    };
  }

  Future<ProductRecord> _ensureProductHasBarcode(ProductRecord product) async {
    if (product.barcode.trim().isNotEmpty) return product;
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) throw Exception('Session topilmadi');
    final generated = _generateLocalBarcode();
    await ref
        .read(productsRepositoryProvider)
        .updateProduct(
          token: session.token,
          id: product.id,
          payload: _payloadFromProduct(product, generated),
        );
    await _reload();
    final bundle = await _future;
    for (final item in bundle.products) {
      if (item.id == product.id) return item;
    }
    throw Exception('Yangilangan mahsulot topilmadi');
  }

  Future<void> _printBarcodeLabel(
    ProductRecord product,
    AppSettingsRecord settings,
  ) async {
    try {
      setState(() => _errorMessage = '');
      final prepared = await _ensureProductHasBarcode(product);
      final barcodeSettings = settings.barcodeLabel;
      final fields = barcodeSettings.fields;

      PdfPageFormat pageFormatBySize() {
        const mm = 72 / 25.4;
        double widthMm;
        double heightMm;
        double marginMm;
        switch (barcodeSettings.paperSize) {
          case '60x40':
            widthMm = 60;
            heightMm = 40;
            marginMm = 2;
            break;
          case '70x50':
            widthMm = 70;
            heightMm = 50;
            marginMm = 2.5;
            break;
          case '80x50':
            widthMm = 80;
            heightMm = 50;
            marginMm = 2.5;
            break;
          case '58x40':
          default:
            widthMm = 58;
            heightMm = 40;
            marginMm = 2;
            break;
        }

        if (barcodeSettings.orientation == 'landscape') {
          final temp = widthMm;
          widthMm = heightMm;
          heightMm = temp;
        }

        return PdfPageFormat(
          widthMm * mm,
          heightMm * mm,
          marginAll: marginMm * mm,
        );
      }

      final barcodeData = prepared.barcode.trim();
      final digitsOnly = barcodeData.replaceAll(RegExp(r'[^0-9]'), '');
      final isEan13 = digitsOnly.length == 13 && digitsOnly == barcodeData;
      final barcode = isEan13 ? bc.Barcode.ean13() : bc.Barcode.code128();

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final doc = pw.Document();

          for (var i = 0; i < barcodeSettings.copies; i++) {
            doc.addPage(
              pw.Page(
                pageFormat: pageFormatBySize(),
                build: (context) {
                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      if (fields.showName)
                        pw.Text(
                          prepared.name.toUpperCase(),
                          maxLines: 1,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      if (fields.showModel && prepared.model.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1.5),
                          child: pw.Text(
                            prepared.model,
                            maxLines: 1,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      if (fields.showCategory &&
                          prepared.category.name.trim().isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 1.2),
                          child: pw.Text(
                            prepared.category.name,
                            maxLines: 1,
                            textAlign: pw.TextAlign.center,
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                        ),
                      pw.SizedBox(height: 3),
                      if (fields.showBarcode)
                        pw.BarcodeWidget(
                          barcode: barcode,
                          data: barcodeData,
                          drawText: true,
                          textStyle: const pw.TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                          ),
                          height: 20,
                        ),
                      if (!fields.showBarcode)
                        pw.Text(
                          barcodeData,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      if (fields.showPrice)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text(
                            'NARX: ${_formatMoney(prepared.retailPrice, settings)}',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          }
          return doc.save();
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _normalizeError(error));
    }
  }

  Future<void> _openCategoryQuickCreate() async {
    final nameController = TextEditingController();
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
              title: const Text('Kategoriya qo\'shish'),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Kategoriya nomi',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Kategoriya nomini kiriting'
                            : null,
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
                            final session = ref
                                .read(authControllerProvider)
                                .valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }
                            await ref
                                .read(categoriesRepositoryProvider)
                                .createCategory(
                                  token: session.token,
                                  name: nameController.text,
                                );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            setLocalState(
                              () => localError = _normalizeError(error),
                            );
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

    nameController.dispose();
  }

  Future<void> _openSupplierQuickCreate() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
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
              title: const Text('Yetkazib beruvchi qo\'shish'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Nomi'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Nom kiriting'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Telefon'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: addressController,
                        decoration: const InputDecoration(labelText: 'Manzil'),
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
                            final session = ref
                                .read(authControllerProvider)
                                .valueOrNull;
                            if (session == null) {
                              throw Exception('Session topilmadi');
                            }
                            await ref
                                .read(suppliersRepositoryProvider)
                                .createSupplier(
                                  token: session.token,
                                  name: nameController.text,
                                  address: addressController.text,
                                  phone: phoneController.text,
                                  openingBalanceAmount: 0,
                                  openingBalanceCurrency: 'uzs',
                                );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await _reload();
                          } catch (error) {
                            setLocalState(
                              () => localError = _normalizeError(error),
                            );
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

    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
  }

  Future<void> _openProductDialog({
    required List<CategoryRecord> categories,
    required List<SupplierRecord> suppliers,
    required AppSettingsRecord settings,
    required List<ProductRecord> allProducts,
    ProductRecord? product,
  }) async {
    final formKey = GlobalKey<FormState>();
    final initialCurrency = product?.priceCurrency ?? 'uzs';
    final initialRate = product?.usdRateUsed ?? settings.usdRate;

    final nameController = TextEditingController(text: product?.name ?? '');
    final modelController = TextEditingController(text: product?.model ?? '');
    final barcodeController = TextEditingController(
      text: product?.barcode ?? '',
    );
    final quantityController = TextEditingController(
      text: product == null
          ? ''
          : ((product.quantity - product.quantity.round()).abs() < 0.0001
                ? product.quantity.round().toString()
                : product.quantity.toStringAsFixed(2)),
    );
    final purchaseController = TextEditingController(
      text: product == null
          ? ''
          : _toEditablePrice(
              product.purchasePrice,
              initialCurrency,
              initialRate,
            ).toStringAsFixed(initialCurrency == 'usd' ? 2 : 0),
    );
    final markupController = TextEditingController(
      text: product != null &&
              product.purchasePrice > 0 &&
              product.retailPrice >= product.purchasePrice
          ? (((product.retailPrice - product.purchasePrice) /
                          product.purchasePrice) *
                      100)
                  .toStringAsFixed(2)
                  .replaceFirst(RegExp(r'\.00$'), '')
          : '',
    );
    final retailController = TextEditingController(
      text: product == null
          ? ''
          : _toEditablePrice(
              product.retailPrice,
              initialCurrency,
              initialRate,
            ).toStringAsFixed(initialCurrency == 'usd' ? 2 : 0),
    );
    final wholesaleController = TextEditingController(
      text: product == null
          ? ''
          : _toEditablePrice(
              product.wholesalePrice,
              initialCurrency,
              initialRate,
            ).toStringAsFixed(initialCurrency == 'usd' ? 2 : 0),
    );
    final paidController = TextEditingController(
      text: product == null
          ? ''
          : _toEditablePrice(
              product.paidAmount,
              initialCurrency,
              initialRate,
            ).toStringAsFixed(initialCurrency == 'usd' ? 2 : 0),
    );
    final pieceQtyController = TextEditingController(
      text: product == null || product.pieceQtyPerBase == 0
          ? ''
          : _formatNumber(product.pieceQtyPerBase),
    );
    final piecePriceController = TextEditingController(
      text: product == null || product.piecePrice == 0
          ? ''
          : _toEditablePrice(
              product.piecePrice,
              initialCurrency,
              initialRate,
            ).toStringAsFixed(initialCurrency == 'usd' ? 2 : 0),
    );

    String categoryId = product?.category.id ?? '';
    String supplierId = product?.supplier.id ?? '';
    String unit = product?.unit ?? 'dona';
    String gender = product?.gender ?? '';
    String paymentType = product?.paymentType ?? 'naqd';
    String currency = initialCurrency;
    String pricingMode = 'keep_old';
    bool allowPieceSale = product?.allowPieceSale ?? false;
    String pieceUnit = product?.pieceUnit ?? _defaultPieceUnitFor(product?.unit ?? 'dona');
    final sizeInputController = TextEditingController(
      text: _joinSizeInput(product?.sizeOptions ?? const <String>[]),
    );
    final selectedSizes = <String>{...product?.sizeOptions ?? const <String>[]};
    final selectedColors = <String>{...product?.colorOptions ?? const <String>[]};
    final variantQtyControllers = <String, TextEditingController>{};
    String localError = '';
    ProductRecord? matchedProduct;
    double matchedOldRetailUzs = 0;
    double matchedOldWholesaleUzs = 0;
    double matchedOldPieceUzs = 0;
    bool applyingStrategy = false;

    String variantKey(String size, String color) => '$size|$color';

    void recalcVariantTotal() {
      if (unit != 'razmer') return;
      final total = variantQtyControllers.values.fold<double>(
        0,
        (sum, controller) => sum + _parseDouble(controller.text),
      );
      quantityController.text = total <= 0
          ? ''
          : ((total - total.round()).abs() < 0.0001
                ? total.round().toString()
                : total.toStringAsFixed(2));
    }

    void syncVariantControllers() {
      if (unit != 'razmer') {
        return;
      }
      final activeKeys = <String>{};
      for (final size in selectedSizes) {
        for (final color in selectedColors) {
          final key = variantKey(size, color);
          activeKeys.add(key);
          variantQtyControllers.putIfAbsent(key, () {
            ProductVariantRecord? existing;
            if (product != null) {
              for (final item in product.variantStocks) {
                if (item.size == size && item.color == color) {
                  existing = item;
                  break;
                }
              }
            }
            return TextEditingController(
              text: existing == null || existing.quantity == 0
                  ? ''
                  : ((existing.quantity - existing.quantity.round()).abs() < 0.0001
                        ? existing.quantity.round().toString()
                        : existing.quantity.toStringAsFixed(2)),
            );
          });
        }
      }
      final removable = variantQtyControllers.keys
          .where((key) => !activeKeys.contains(key))
          .toList();
      for (final key in removable) {
        variantQtyControllers.remove(key)?.dispose();
      }
      recalcVariantTotal();
    }

    void applySizeInput() {
      selectedSizes
        ..clear()
        ..addAll(_normalizeSizeInput(sizeInputController.text));
      syncVariantControllers();
    }

    void applyMarkupToRetail() {
      final purchasePrice = _parseDouble(purchaseController.text);
      final markup = _parseDouble(markupController.text);
      if (purchasePrice <= 0 || markupController.text.trim().isEmpty) return;
      final retail = purchasePrice * (1 + (markup / 100));
      retailController.text = retail.toStringAsFixed(currency == 'usd' ? 2 : 0);
    }

    if (unit == 'razmer') {
      syncVariantControllers();
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            void fillFromExisting(ProductRecord existing) {
              if (product != null) return;
              final targetCurrency = existing.priceCurrency;
              final targetRate = existing.usdRateUsed > 0
                  ? existing.usdRateUsed
                  : settings.usdRate;
              String format(double value) => _toEditablePrice(
                value,
                targetCurrency,
                targetRate,
              ).toStringAsFixed(targetCurrency == 'usd' ? 2 : 0);

              nameController.text = existing.name;
              modelController.text = existing.model;
              barcodeController.text = existing.barcode;
              purchaseController.text = format(existing.purchasePrice);
              retailController.text = format(existing.retailPrice);
              wholesaleController.text = format(existing.wholesalePrice);
              markupController.text =
                  existing.purchasePrice > 0 &&
                      existing.retailPrice >= existing.purchasePrice
                  ? (((existing.retailPrice - existing.purchasePrice) /
                                  existing.purchasePrice) *
                              100)
                          .toStringAsFixed(2)
                          .replaceFirst(RegExp(r'\.00$'), '')
                  : '';
              paidController.text = '0';
              pieceQtyController.text = existing.pieceQtyPerBase > 0
                  ? _formatNumber(existing.pieceQtyPerBase)
                  : '';
              piecePriceController.text = existing.piecePrice > 0
                  ? format(existing.piecePrice)
                  : '';
              quantityController.text = '0';
              setLocalState(() {
                matchedProduct = existing;
                categoryId = existing.category.id;
                supplierId = existing.supplier.id;
                unit = existing.unit;
                gender = existing.gender;
                paymentType = existing.paymentType;
                currency = targetCurrency;
                allowPieceSale = existing.allowPieceSale;
                pieceUnit = existing.pieceUnit;
                pricingMode = 'keep_old';
                sizeInputController.text = _joinSizeInput(existing.sizeOptions);
                selectedSizes
                  ..clear()
                  ..addAll(existing.sizeOptions);
                selectedColors
                  ..clear()
                  ..addAll(existing.colorOptions);
                syncVariantControllers();
              });
              matchedOldRetailUzs = existing.retailPrice;
              matchedOldWholesaleUzs = existing.wholesalePrice;
              matchedOldPieceUzs = existing.piecePrice;
            }

            String editableText(double uzsValue) {
              final double rate = settings.usdRate <= 0
                  ? 1.0
                  : settings.usdRate.toDouble();
              final editable = _toEditablePrice(uzsValue, currency, rate);
              return editable.toStringAsFixed(currency == 'usd' ? 2 : 0);
            }

            double toUzs(double editableValue) {
              if (currency == 'usd' && settings.usdRate > 0) {
                return editableValue * settings.usdRate;
              }
              return editableValue;
            }

            void applyPricingModeChange(String mode) {
              if (matchedProduct == null || product != null) return;
              applyingStrategy = true;
              if (mode == 'replace_all') {
                retailController.text = currency == 'usd' ? '0.00' : '0';
                wholesaleController.text = currency == 'usd' ? '0.00' : '0';
                if (allowPieceSale) {
                  piecePriceController.text = currency == 'usd' ? '0.00' : '0';
                }
              } else if (mode == 'keep_old') {
                retailController.text = editableText(matchedOldRetailUzs);
                wholesaleController.text = editableText(matchedOldWholesaleUzs);
                if (allowPieceSale) {
                  piecePriceController.text = editableText(matchedOldPieceUzs);
                }
              }
              applyingStrategy = false;
            }

            void applyAverageForController(
              TextEditingController controller,
              double oldUzs,
            ) {
              if (applyingStrategy) return;
              if (matchedProduct == null || product != null) return;
              if (pricingMode != 'average') return;
              final enteredEditable = _parseDouble(controller.text);
              final enteredUzs = toUzs(enteredEditable);
              final averageUzs = (oldUzs + enteredUzs) / 2.0;
              applyingStrategy = true;
              controller.text = editableText(averageUzs);
              applyingStrategy = false;
            }

            void lookupBarcode(String code) {
              if (product != null) return;
              final normalizedInput = code.trim().toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9]'),
                '',
              );
              if (normalizedInput.isEmpty) {
                setLocalState(() => matchedProduct = null);
                return;
              }
              ProductRecord? found;
              for (final item in allProducts) {
                final itemNormalized = item.barcode
                    .trim()
                    .toLowerCase()
                    .replaceAll(RegExp(r'[^a-z0-9]'), '');
                if (itemNormalized.isNotEmpty &&
                    itemNormalized == normalizedInput) {
                  found = item;
                  break;
                }
              }
              if (found != null) {
                fillFromExisting(found);
              } else {
                setLocalState(() => matchedProduct = null);
              }
            }

            final quantity = _parseDouble(quantityController.text);
            final purchasePrice = _parseDouble(purchaseController.text);
            final total = quantity * purchasePrice;
            final effectivePaid = paymentType == 'naqd'
                ? total
                : paymentType == 'qarz'
                ? 0
                : _parseDouble(paidController.text);
            final debt = total - effectivePaid;

            return Dialog(
              backgroundColor: const Color(0xFF17284B),
              insetPadding: const EdgeInsets.all(28),
              child: SizedBox(
                width: 900,
                height: 760,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product == null
                              ? 'Yangi mahsulot qo\'shish'
                              : 'Mahsulotni tahrirlash',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _DialogSectionTitle(
                                  'Asosiy ma\'lumotlar',
                                ),
                                const SizedBox(height: 12),
                                _DialogGrid(
                                  children: [
                                    TextFormField(
                                      controller: nameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Mahsulot nomi',
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Mahsulot nomini kiriting'
                                          : null,
                                    ),
                                    TextFormField(
                                      controller: modelController,
                                      decoration: const InputDecoration(
                                        labelText: 'Modeli',
                                      ),
                                      validator: (value) =>
                                          value == null || value.trim().isEmpty
                                          ? 'Modelni kiriting'
                                          : null,
                                    ),
                                    TextFormField(
                                      controller: barcodeController,
                                      decoration: InputDecoration(
                                        labelText: 'Shtixkod',
                                        suffixIcon: IconButton(
                                          tooltip: 'Auto generate',
                                          onPressed: () {
                                            setLocalState(() {
                                              barcodeController.text =
                                                  _generateLocalBarcode();
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.qr_code_2_rounded,
                                          ),
                                        ),
                                      ),
                                      onFieldSubmitted: (_) =>
                                          lookupBarcode(barcodeController.text),
                                      onChanged: (value) {
                                        if (value.trim().isEmpty) {
                                          setLocalState(
                                            () => matchedProduct = null,
                                          );
                                          return;
                                        }
                                        lookupBarcode(value);
                                      },
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: unit,
                                      decoration: const InputDecoration(
                                        labelText: 'Birligi',
                                      ),
                                      items: _productUnits
                                          .map(
                                            (item) => DropdownMenuItem(
                                              value: item,
                                              child: Text(item),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          unit = value ?? 'dona';
                                          if (!_supportsPieceSale(unit)) {
                                            allowPieceSale = false;
                                            pieceUnit = _defaultPieceUnitFor(unit);
                                            pieceQtyController.text = '';
                                            piecePriceController.text = '';
                                          } else {
                                            pieceUnit = _defaultPieceUnitFor(unit);
                                          }
                                          if (unit == 'razmer') {
                                            allowPieceSale = false;
                                            applySizeInput();
                                            syncVariantControllers();
                                          } else {
                                            sizeInputController.text = '';
                                            selectedSizes.clear();
                                            selectedColors.clear();
                                            for (final controller
                                                in variantQtyControllers.values) {
                                              controller.dispose();
                                            }
                                            variantQtyControllers.clear();
                                          }
                                        });
                                      },
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: categoryId.isEmpty
                                          ? null
                                          : categoryId,
                                      decoration: const InputDecoration(
                                        labelText: 'Kategoriya',
                                      ),
                                      items: categories
                                          .map(
                                            (item) => DropdownMenuItem(
                                              value: item.id,
                                              child: Text(item.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setLocalState(
                                          () => categoryId = value ?? '',
                                        );
                                      },
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Kategoriya tanlang'
                                          : null,
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: supplierId.isEmpty
                                          ? null
                                          : supplierId,
                                      decoration: const InputDecoration(
                                        labelText: 'Yetkazib beruvchi',
                                      ),
                                      items: suppliers
                                          .map(
                                            (item) => DropdownMenuItem(
                                              value: item.id,
                                              child: Text(item.name),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setLocalState(
                                          () => supplierId = value ?? '',
                                        );
                                      },
                                      validator: (value) =>
                                          value == null || value.isEmpty
                                          ? 'Yetkazib beruvchi tanlang'
                                          : null,
                                    ),
                                    TextFormField(
                                      controller: quantityController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: unit == 'razmer'
                                            ? 'Jami miqdor'
                                            : 'Miqdori',
                                        hintText: unit == 'razmer'
                                            ? 'Qo‘lda kiriting yoki variantlardan to‘lsin'
                                            : null,
                                      ),
                                      validator: (value) =>
                                          _parseDouble(value ?? '') <= 0
                                          ? 'Miqdor kiriting'
                                          : null,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Jinsi',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SegmentedButton<String>(
                                        segments: _productGenders
                                            .map(
                                              (item) => ButtonSegment<String>(
                                                value: item,
                                                label: Text(_genderLabel(item)),
                                              ),
                                            )
                                            .toList(),
                                        selected: {gender},
                                        onSelectionChanged: (selection) {
                                          setLocalState(() {
                                            gender = selection.isEmpty
                                                ? ''
                                                : selection.first;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                if (unit == 'razmer') ...[
                                  const SizedBox(height: 18),
                                  const _DialogSectionTitle('Razmer va ranglar'),
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF102244),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFF244A7C),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ranglarni tanlang',
                                          style: Theme.of(dialogContext)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: 44,
                                          child: ElevatedButton.icon(
                                            onPressed: () async {
                                              final picked =
                                                  await showDialog<Set<String>>(
                                                    context: dialogContext,
                                                    builder: (colorContext) {
                                                      final draft = <String>{
                                                        ...selectedColors,
                                                      };
                                                      return StatefulBuilder(
                                                        builder: (
                                                          context,
                                                          setColorState,
                                                        ) {
                                                          return Dialog(
                                                            backgroundColor:
                                                                Colors.transparent,
                                                            insetPadding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 24,
                                                                  vertical: 24,
                                                                ),
                                                            child: Container(
                                                              width: 720,
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    28,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: const Color(
                                                                  0xFF1D2D57,
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      28,
                                                                    ),
                                                              ),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize.min,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  const Text(
                                                                    'Ranglarni tanlang',
                                                                    style: TextStyle(
                                                                      fontSize: 24,
                                                                      fontWeight:
                                                                          FontWeight.w700,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 24,
                                                                  ),
                                                                  Wrap(
                                                                    spacing: 14,
                                                                    runSpacing: 14,
                                                                    children:
                                                                        _productColors.map((
                                                                          color,
                                                                        ) {
                                                                          return _ColorChoiceButton(
                                                                            label:
                                                                                color,
                                                                            color:
                                                                                _colorForLabel(
                                                                                  color,
                                                                                ),
                                                                            selected:
                                                                                draft.contains(
                                                                                  color,
                                                                                ),
                                                                            onTap:
                                                                                () {
                                                                                  setColorState(
                                                                                    () {
                                                                                      if (draft.contains(
                                                                                        color,
                                                                                      )) {
                                                                                        draft.remove(
                                                                                          color,
                                                                                        );
                                                                                      } else {
                                                                                        draft.add(
                                                                                          color,
                                                                                        );
                                                                                      }
                                                                                    },
                                                                                  );
                                                                                },
                                                                          );
                                                                        }).toList(),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 28,
                                                                  ),
                                                                  Align(
                                                                    alignment:
                                                                        Alignment.centerRight,
                                                                    child: TextButton(
                                                                      onPressed: () => Navigator.of(
                                                                        colorContext,
                                                                      ).pop(),
                                                                      child: const Text(
                                                                        'Bekor qilish',
                                                                        style: TextStyle(
                                                                          fontSize: 16,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 8,
                                                                  ),
                                                                  SizedBox(
                                                                    width: double.infinity,
                                                                    height: 58,
                                                                    child: ElevatedButton(
                                                                      onPressed: () => Navigator.of(
                                                                        colorContext,
                                                                      ).pop(draft),
                                                                      style: ElevatedButton.styleFrom(
                                                                        shape: RoundedRectangleBorder(
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                20,
                                                                              ),
                                                                        ),
                                                                      ),
                                                                      child: const Text(
                                                                        'Saqlash',
                                                                        style: TextStyle(
                                                                          fontSize: 18,
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                        ),
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
                                              if (picked != null) {
                                                setLocalState(() {
                                                  selectedColors
                                                    ..clear()
                                                    ..addAll(picked);
                                                  syncVariantControllers();
                                                });
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.palette_outlined,
                                            ),
                                            label: const Text('Rang tanlash'),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: selectedColors.isEmpty
                                              ? const [
                                                  _ColorPreviewCard(
                                                    label:
                                                        'Hali rang tanlanmagan',
                                                    selected: false,
                                                  ),
                                                ]
                                              : selectedColors
                                                    .map(
                                                      (color) =>
                                                          _ColorPreviewCard(
                                                            label: color,
                                                            selected: true,
                                                          ),
                                                    )
                                                    .toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: sizeInputController,
                                    decoration: const InputDecoration(
                                      labelText: 'Razmerlar',
                                      hintText: 'Masalan: x 4-6 41 43',
                                    ),
                                    onChanged: (_) {
                                      setLocalState(applySizeInput);
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  if (selectedSizes.isNotEmpty && selectedColors.isNotEmpty)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF102244),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        children: [
                                          for (final size in selectedSizes)
                                            for (final color in selectedColors) ...[
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Razmer $size • $color',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(
                                                    width: 120,
                                                    child: TextFormField(
                                                      controller: variantQtyControllers[variantKey(size, color)],
                                                      keyboardType: const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                      decoration: const InputDecoration(
                                                        labelText: 'Qoldiq',
                                                      ),
                                                      onChanged: (_) {
                                                        setLocalState(recalcVariantTotal);
                                                      },
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                        ],
                                      ),
                                    ),
                                ],
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: FilledButton.tonal(
                                    onPressed: _saving
                                        ? null
                                        : _openSupplierQuickCreate,
                                    child: const Text(
                                      '+ Yangi yetkazib beruvchi',
                                    ),
                                  ),
                                ),
                                if (matchedProduct != null && product == null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      'Mahsulot omborda bor — kirim miqdorini kiriting.',
                                      style: TextStyle(
                                        color: Colors.teal[200],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 18),
                                const _DialogSectionTitle('Narxlar'),
                                const SizedBox(height: 12),
                                _DialogGrid(
                                  children: [
                                    DropdownButtonFormField<String>(
                                      initialValue: currency,
                                      decoration: const InputDecoration(
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
                                      onChanged: (value) {
                                        setLocalState(
                                          () => currency = value ?? 'uzs',
                                        );
                                      },
                                    ),
                                    TextFormField(
                                      controller: purchaseController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Kelish narxi',
                                      ),
                                      onChanged: (_) {
                                        setLocalState(applyMarkupToRetail);
                                      },
                                    ),
                                    TextFormField(
                                      controller: markupController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Ustama %',
                                        hintText: 'Masalan 10',
                                      ),
                                      onChanged: (_) {
                                        setLocalState(applyMarkupToRetail);
                                      },
                                    ),
                                    if (matchedProduct != null &&
                                        product == null)
                                      DropdownButtonFormField<String>(
                                        initialValue: pricingMode,
                                        decoration: const InputDecoration(
                                          labelText: 'Narx strategiyasi',
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: 'keep_old',
                                            child: Text('Eski narxni saqlash'),
                                          ),
                                          DropdownMenuItem(
                                            value: 'replace_all',
                                            child: Text(
                                              'Yangi narxni qo\'llash',
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'average',
                                            child: Text(
                                              'Eski+yangi o\'rtacha narx',
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          setLocalState(
                                            () => pricingMode =
                                                value ?? 'keep_old',
                                          );
                                          applyPricingModeChange(
                                            value ?? 'keep_old',
                                          );
                                        },
                                      ),
                                    TextFormField(
                                      controller: retailController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: _supportsPieceSale(unit)
                                            ? '${_baseUnitLabel(unit)[0].toUpperCase()}${_baseUnitLabel(unit).substring(1)} narxi (chakana)'
                                            : 'Dona narxi',
                                      ),
                                      onChanged: (_) =>
                                          applyAverageForController(
                                            retailController,
                                            matchedOldRetailUzs,
                                          ),
                                    ),
                                    TextFormField(
                                      controller: wholesaleController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: _supportsPieceSale(unit)
                                            ? '${_baseUnitLabel(unit)[0].toUpperCase()}${_baseUnitLabel(unit).substring(1)} narxi (optom)'
                                            : 'Optom narxi',
                                      ),
                                      onChanged: (_) =>
                                          applyAverageForController(
                                            wholesaleController,
                                            matchedOldWholesaleUzs,
                                          ),
                                    ),
                                    DropdownButtonFormField<String>(
                                      initialValue: paymentType,
                                      decoration: const InputDecoration(
                                        labelText: 'To\'lov turi',
                                      ),
                                      items: _paymentTypes
                                          .map(
                                            (item) => DropdownMenuItem(
                                              value: item,
                                              child: Text(item),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setLocalState(() {
                                          paymentType = value ?? 'naqd';
                                          if (paymentType == 'naqd') {
                                            paidController.text = total
                                                .toStringAsFixed(
                                                  currency == 'usd' ? 2 : 0,
                                                );
                                          } else if (paymentType == 'qarz') {
                                            paidController.text = '0';
                                          }
                                        });
                                      },
                                    ),
                                    TextFormField(
                                      controller: paidController,
                                      readOnly: paymentType != 'qisman',
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'To\'langan summa',
                                        hintText: paymentType == 'naqd'
                                            ? 'Avto: to\'liq'
                                            : paymentType == 'qarz'
                                            ? 'Avto: 0'
                                            : null,
                                      ),
                                      validator: (value) {
                                        final paid = _parseDouble(value ?? '');
                                        if (paid < 0) {
                                          return 'Summa noto\'g\'ri';
                                        }
                                        if (paid > total) {
                                          return 'To\'langan summa umumiy summadan katta';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF102244),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Umumiy kelish summasi: ${_formatNumber(total)} ${currency == 'usd' ? '\$' : 'so\'m'}',
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Joriy qarz: ${_formatNumber(debt < 0 ? 0 : debt)} ${currency == 'usd' ? '\$' : 'so\'m'}',
                                      ),
                                    ],
                                  ),
                                ),
                                if (_supportsPieceSale(unit)) ...[
                                  const SizedBox(height: 18),
                                  _DialogSectionTitle(
                                    '${_baseUnitLabel(unit)[0].toUpperCase()}${_baseUnitLabel(unit).substring(1)} bo\'lib sotish',
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    value: allowPieceSale,
                                    onChanged: (value) {
                                      setLocalState(
                                        () => allowPieceSale = value,
                                      );
                                    },
                                    title: Text(
                                      '${_baseUnitLabel(unit)[0].toUpperCase()}${_baseUnitLabel(unit).substring(1)}ni bo\'lib sotish',
                                    ),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  if (allowPieceSale)
                                    _DialogGrid(
                                      children: [
                                        DropdownButtonFormField<String>(
                                          initialValue: pieceUnit,
                                          decoration: InputDecoration(
                                            labelText: unit == 'pachka'
                                                ? 'Ichidagi birlik'
                                                : 'Parcha birligi',
                                          ),
                                          items: _productUnits
                                              .where((item) => item != 'razmer')
                                              .map(
                                                (item) => DropdownMenuItem(
                                                  value: item,
                                                  child: Text(item),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            setLocalState(
                                              () => pieceUnit = value ?? 'kg',
                                            );
                                          },
                                        ),
                                        TextFormField(
                                          controller: pieceQtyController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: unit == 'pachka'
                                                ? '1 pachkada nechta $pieceUnit bor'
                                                : '1 qop ichidagi $pieceUnit',
                                          ),
                                          validator: (value) =>
                                              allowPieceSale &&
                                                  _parseDouble(value ?? '') <= 0
                                              ? 'Miqdor kiriting'
                                              : null,
                                        ),
                                        TextFormField(
                                          controller: piecePriceController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: '1 $pieceUnit narxi',
                                          ),
                                          onChanged: (_) =>
                                              applyAverageForController(
                                                piecePriceController,
                                                matchedOldPieceUzs,
                                              ),
                                          validator: (value) =>
                                              allowPieceSale &&
                                                  _parseDouble(value ?? '') <= 0
                                              ? 'Narx kiriting'
                                              : null,
                                        ),
                                      ],
                                    ),
                                ],
                                if (localError.isNotEmpty) ...[
                                  const SizedBox(height: 14),
                                  Text(
                                    localError,
                                    style: const TextStyle(
                                      color: Color(0xFFFF8A8A),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text('Bekor qilish'),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 180,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate()) {
                                          return;
                                        }
                                        setState(() {
                                          _saving = true;
                                          _errorMessage = '';
                                        });
                                        setLocalState(() => localError = '');
                                        try {
                                          final session = ref
                                              .read(authControllerProvider)
                                              .valueOrNull;
                                          if (session == null) {
                                            throw Exception(
                                              'Session topilmadi',
                                            );
                                          }

                                          final payload = <String, dynamic>{
                                            'name': nameController.text.trim(),
                                            'model': modelController.text
                                                .trim(),
                                            'barcode': barcodeController.text
                                                .trim(),
                                            'gender': gender,
                                            'categoryId': categoryId,
                                            'supplierId': supplierId,
                                            'purchasePrice': _parseDouble(
                                              purchaseController.text,
                                            ),
                                            'priceCurrency': currency,
                                            'retailPrice': _parseDouble(
                                              retailController.text,
                                            ),
                                            'wholesalePrice': _parseDouble(
                                              wholesaleController.text,
                                            ),
                                            'paymentType': paymentType,
                                            'paidAmount': paymentType == 'naqd'
                                                ? _parseDouble(
                                                        quantityController.text,
                                                      ) *
                                                      _parseDouble(
                                                        purchaseController.text,
                                                      )
                                                : paymentType == 'qarz'
                                                ? 0
                                                : _parseDouble(
                                                    paidController.text,
                                                  ),
                                            'quantity': _parseDouble(
                                              quantityController.text,
                                            ),
                                            'unit': unit,
                                            'sizeOptions': selectedSizes.toList(),
                                            'colorOptions': selectedColors.toList(),
                                            'variantStocks': unit == 'razmer'
                                                ? selectedSizes
                                                      .expand(
                                                        (size) => selectedColors.map(
                                                          (color) => {
                                                            'size': size,
                                                            'color': color,
                                                            'quantity': _parseDouble(
                                                              variantQtyControllers[variantKey(size, color)]?.text ?? '',
                                                            ),
                                                          },
                                                        ),
                                                      )
                                                      .where(
                                                        (item) => (item['quantity'] as double) > 0,
                                                      )
                                                      .toList()
                                                : <Map<String, dynamic>>[],
                                            'allowPieceSale': allowPieceSale,
                                            'pieceUnit': pieceUnit,
                                            'pieceQtyPerBase': allowPieceSale
                                                ? _parseDouble(
                                                    pieceQtyController.text,
                                                  )
                                                : 0,
                                            'piecePrice': allowPieceSale
                                                ? _parseDouble(
                                                    piecePriceController.text,
                                                  )
                                                : 0,
                                          };

                                          final repo = ref.read(
                                            productsRepositoryProvider,
                                          );
                                          if (product == null &&
                                              matchedProduct != null) {
                                            final restockPayload = {
                                              'supplierId': supplierId,
                                              'quantity': _parseDouble(
                                                quantityController.text,
                                              ),
                                              'purchasePrice': _parseDouble(
                                                purchaseController.text,
                                              ),
                                              'priceCurrency': currency,
                                              'pricingMode': pricingMode,
                                              'retailPrice': _parseDouble(
                                                retailController.text,
                                              ),
                                              'wholesalePrice': _parseDouble(
                                                wholesaleController.text,
                                              ),
                                              'piecePrice': allowPieceSale
                                                  ? _parseDouble(
                                                      piecePriceController.text,
                                                    )
                                                  : 0,
                                              'paymentType': paymentType,
                                              'paidAmount':
                                                  paymentType == 'naqd'
                                                  ? _parseDouble(
                                                          quantityController
                                                              .text,
                                                        ) *
                                                        _parseDouble(
                                                          purchaseController
                                                              .text,
                                                        )
                                                  : paymentType == 'qarz'
                                                  ? 0
                                                  : _parseDouble(
                                                      paidController.text,
                                                    ),
                                            };
                                            await repo.restockProduct(
                                              token: session.token,
                                              id: matchedProduct!.id,
                                              payload: restockPayload,
                                            );
                                          } else if (product == null) {
                                            await repo.createProduct(
                                              token: session.token,
                                              payload: payload,
                                            );
                                          } else {
                                            await repo.updateProduct(
                                              token: session.token,
                                              id: product.id,
                                              payload: payload,
                                            );
                                          }

                                          if (!dialogContext.mounted) return;
                                          Navigator.of(dialogContext).pop();
                                          await _reload();
                                        } catch (error) {
                                          setLocalState(
                                            () => localError = _normalizeError(
                                              error,
                                            ),
                                          );
                                        } finally {
                                          if (mounted) {
                                            setState(() => _saving = false);
                                          }
                                        }
                                      },
                                child: Text(
                                  _saving
                                      ? 'Saqlanmoqda...'
                                      : (product == null &&
                                            matchedProduct != null)
                                      ? 'Kirimni saqlash'
                                      : 'Saqlash',
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
            );
          },
        );
      },
    );

      nameController.dispose();
      modelController.dispose();
      barcodeController.dispose();
      quantityController.dispose();
      purchaseController.dispose();
      markupController.dispose();
      retailController.dispose();
      wholesaleController.dispose();
      paidController.dispose();
      pieceQtyController.dispose();
      piecePriceController.dispose();
      sizeInputController.dispose();
      for (final controller in variantQtyControllers.values) {
        controller.dispose();
      }
  }

  Future<void> _deleteProduct(ProductRecord product) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17284B),
          title: const Text('Mahsulotni o\'chirish'),
          content: Text('"${product.name}" mahsulotini o\'chirasizmi?'),
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
          .read(productsRepositoryProvider)
          .deleteProduct(token: session.token, id: product.id);
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _normalizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncProductsFromCentral() async {
    try {
      setState(() {
        _saving = true;
        _errorMessage = '';
      });
      final session = ref.read(authControllerProvider).valueOrNull;
      if (session == null) throw Exception('Session topilmadi');
      final result = await ref
          .read(productsRepositoryProvider)
          .syncCentralTransfers(token: session.token);
      await _reload();
      if (!mounted) return;
      final message =
          result['message']?.toString() ?? 'Sinxron yakunlandi';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _normalizeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProductsBundle>(
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

        final bundle = snapshot.data!;
        final settings = bundle.settings;
        final query = _search.trim().toLowerCase();
        final filtered = bundle.products.where((product) {
          final matchesCategory =
              _selectedCategoryId.isEmpty ||
              product.category.id == _selectedCategoryId;
          final searchText = [
            product.name,
            product.model,
            product.barcode,
            product.category.name,
            product.supplier.name,
            product.unit,
            product.paymentType,
          ].join(' ').toLowerCase();
          final matchesQuery = query.isEmpty || searchText.contains(query);
          return matchesCategory && matchesQuery;
        }).toList();

        final totalPages = filtered.isEmpty
            ? 1
            : (filtered.length / _pageSize).ceil();
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
                Expanded(
                  child: SizedBox(
                    height: 48,
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
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 260,
                  height: 48,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId.isEmpty
                        ? ''
                        : _selectedCategoryId,
                    decoration: const InputDecoration(
                      hintText: 'Barcha kategoriyalar',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Barcha kategoriyalar'),
                      ),
                      ...bundle.categories.map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedCategoryId = value ?? '';
                        _page = 1;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                _TopActionButton(
                  label: '+ Kategoriya',
                  onTap: _saving ? null : _openCategoryQuickCreate,
                ),
                const SizedBox(width: 8),
                _TopActionButton(
                  label: '+ Yetkazib beruvchi',
                  onTap: _saving ? null : _openSupplierQuickCreate,
                ),
                const SizedBox(width: 8),
                _TopActionButton(
                  label: '+ Mahsulot qo\'shish',
                  onTap: _saving
                      ? null
                      : () => _openProductDialog(
                          categories: bundle.categories,
                          suppliers: bundle.suppliers,
                          settings: settings,
                          allProducts: bundle.products,
                        ),
                ),
                const SizedBox(width: 8),
                _TopActionButton(
                  label: 'Sinxron',
                  onTap: _saving ? null : _syncProductsFromCentral,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: constraints.maxWidth > 1940
                          ? constraints.maxWidth
                          : 1940,
                      height: constraints.maxHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF223D72),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF345891)),
                        ),
                        child: Column(
                          children: [
                            const _ProductsHeaderRow(),
                            Expanded(
                              child: pageItems.isEmpty
                                  ? const Center(
                                      child: Text('Mahsulot topilmadi'),
                                    )
                                  : ListView.separated(
                                      itemCount: pageItems.length,
                                      separatorBuilder: (context, index) =>
                                          const Divider(
                                            height: 1,
                                            color: Color(0xFF2F4B7F),
                                          ),
                                      itemBuilder: (context, index) {
                                        final product = pageItems[index];
                                        return _ProductsDataRow(
                                          index: start + index + 1,
                                          product: product,
                                          formatMoney: (amount) =>
                                              _formatMoney(amount, settings),
                                          paymentText: _formatDebt(
                                            product,
                                            settings,
                                          ),
                                          stockNote: _formatStockNote(
                                            product,
                                            settings,
                                          ),
                                          isLowStock:
                                              product.quantity <=
                                              settings.lowStockThreshold,
                                        );
                                      },
                                    ),
                            ),
                            _ProductsPagination(
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

class _ProductsBundle {
  const _ProductsBundle({
    required this.products,
    required this.categories,
    required this.suppliers,
    required this.settings,
  });

  final List<ProductRecord> products;
  final List<CategoryRecord> categories;
  final List<SupplierRecord> suppliers;
  final AppSettingsRecord settings;
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
    );
  }
}

class _DialogGrid extends StatelessWidget {
  const _DialogGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < children.length; index += 2) ...[
          if (index + 1 >= children.length)
            children[index]
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children[index]),
                const SizedBox(width: 12),
                Expanded(child: children[index + 1]),
              ],
            ),
          if (index + 2 < children.length) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ColorPreviewCard extends StatelessWidget {
  const _ColorPreviewCard({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF244A7C) : const Color(0xFF17284B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFF3BA5F4) : const Color(0xFF2D4770),
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ColorChoiceButton extends StatelessWidget {
  const _ColorChoiceButton({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = _colorTextFor(color);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.white : color.withValues(alpha: 0.78),
            width: selected ? 2.4 : 1.2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, color: textColor, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _ProductsHeaderRow extends StatelessWidget {
  const _ProductsHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF3A5D98),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: const Row(
        children: [
          _ProductsCell(flex: 28, label: 'Mahsulot nomi', header: true),
          _ProductsCell(flex: 16, label: 'Modeli', header: true),
          _ProductsCell(flex: 14, label: 'Jinsi', header: true),
          _ProductsCell(flex: 18, label: 'Shtixkod', header: true),
          _ProductsCell(flex: 18, label: 'Kategoriya', header: true),
          _ProductsCell(flex: 18, label: 'Yetkazib beruvchi', header: true),
          _ProductsCell(flex: 13, label: 'Kelish narxi', header: true),
          _ProductsCell(flex: 13, label: 'Dona narxi', header: true),
          _ProductsCell(flex: 14, label: 'Optom narxi', header: true),
          _ProductsCell(flex: 16, label: 'To\'lov / Qarz', header: true),
          _ProductsCell(flex: 18, label: 'Xisobot', header: true),
          _ProductsCell(flex: 10, label: 'Miqdori', header: true),
          _ProductsCell(flex: 10, label: 'Birligi', header: true),
        ],
      ),
    );
  }
}

class _ProductsDataRow extends StatelessWidget {
  const _ProductsDataRow({
    required this.index,
    required this.product,
    required this.formatMoney,
    required this.paymentText,
    required this.stockNote,
    required this.isLowStock,
  });

  final int index;
  final ProductRecord product;
  final String Function(double amount) formatMoney;
  final String paymentText;
  final String stockNote;
  final bool isLowStock;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: index.isEven ? const Color(0xFF203863) : const Color(0xFF1C325B),
      child: Row(
        children: [
          _ProductsCell(flex: 28, label: product.name),
          _ProductsCell(flex: 16, label: product.model),
          _ProductsCell(flex: 14, label: _genderLabel(product.gender)),
          _ProductsCell(
            flex: 18,
            label: product.barcode.isEmpty ? '-' : product.barcode,
          ),
          _ProductsCell(flex: 18, label: product.category.name),
          _ProductsCell(flex: 18, label: product.supplier.name),
          _ProductsCell(flex: 13, label: formatMoney(product.purchasePrice)),
          _ProductsCell(flex: 13, label: formatMoney(product.retailPrice)),
          _ProductsCell(flex: 14, label: formatMoney(product.wholesalePrice)),
          _ProductsCell(flex: 16, label: paymentText),
          _ProductsCell(flex: 18, label: stockNote),
          _ProductsCell(
            flex: 10,
            label: product.quantity % 1 == 0
                ? product.quantity.round().toString()
                : product.quantity.toStringAsFixed(2),
            color: isLowStock ? const Color(0xFFFF6B6B) : null,
            weight: isLowStock ? FontWeight.w800 : FontWeight.w600,
          ),
          _ProductsCell(flex: 10, label: product.unit),
        ],
      ),
    );
  }
}

class _ProductsCell extends StatelessWidget {
  const _ProductsCell({
    required this.flex,
    required this.label,
    this.header = false,
    this.color,
    this.weight,
  });

  final int flex;
  final String label;
  final bool header;
  final Color? color;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: header ? 14 : 13,
            fontWeight: weight ?? (header ? FontWeight.w800 : FontWeight.w500),
            color: color ?? Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ProductsPagination extends StatelessWidget {
  const _ProductsPagination({
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
