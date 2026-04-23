class ProductCategoryRef {
  const ProductCategoryRef({required this.id, required this.name});

  final String id;
  final String name;

  factory ProductCategoryRef.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return ProductCategoryRef(
        id: json['_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Kategoriyasiz',
      );
    }
    if (json is Map) {
      return ProductCategoryRef(
        id: json['_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Kategoriyasiz',
      );
    }
    return ProductCategoryRef(
      id: json?.toString() ?? '',
      name: 'Kategoriyasiz',
    );
  }
}

class ProductSupplierRef {
  const ProductSupplierRef({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
  });

  final String id;
  final String name;
  final String phone;
  final String address;

  factory ProductSupplierRef.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return ProductSupplierRef(
        id: json['_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Yetkazib beruvchi yo\'q',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
      );
    }
    if (json is Map) {
      return ProductSupplierRef(
        id: json['_id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Yetkazib beruvchi yo\'q',
        phone: json['phone']?.toString() ?? '',
        address: json['address']?.toString() ?? '',
      );
    }
    return ProductSupplierRef(
      id: json?.toString() ?? '',
      name: 'Yetkazib beruvchi yo\'q',
      phone: '',
      address: '',
    );
  }
}

class ProductVariantRecord {
  const ProductVariantRecord({
    required this.size,
    required this.color,
    required this.quantity,
  });

  final String size;
  final String color;
  final double quantity;

  factory ProductVariantRecord.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return ProductVariantRecord(
        size: json['size']?.toString() ?? '',
        color: json['color']?.toString() ?? '',
        quantity: _toDouble(json['quantity']),
      );
    }
    if (json is Map) {
      return ProductVariantRecord(
        size: json['size']?.toString() ?? '',
        color: json['color']?.toString() ?? '',
        quantity: _toDouble(json['quantity']),
      );
    }
    return const ProductVariantRecord(size: '', color: '', quantity: 0);
  }
}

class ProductRecord {
  const ProductRecord({
    required this.id,
    required this.name,
    required this.model,
    required this.barcode,
    this.barcodeAliases = const [],
    required this.productCode,
    required this.gender,
    required this.category,
    required this.supplier,
    required this.purchasePrice,
    required this.priceCurrency,
    required this.usdRateUsed,
    required this.totalPurchaseCost,
    required this.retailPrice,
    required this.wholesalePrice,
    required this.paymentType,
    required this.paidAmount,
    required this.debtAmount,
    required this.quantity,
    required this.unit,
    required this.sizeOptions,
    required this.colorOptions,
    required this.variantStocks,
    required this.allowPieceSale,
    required this.pieceUnit,
    required this.pieceQtyPerBase,
    required this.piecePrice,
  });

  final String id;
  final String name;
  final String model;
  final String barcode;
  final List<String> barcodeAliases;
  final String productCode;
  final String gender;
  final ProductCategoryRef category;
  final ProductSupplierRef supplier;
  final double purchasePrice;
  final String priceCurrency;
  final double usdRateUsed;
  final double totalPurchaseCost;
  final double retailPrice;
  final double wholesalePrice;
  final String paymentType;
  final double paidAmount;
  final double debtAmount;
  final double quantity;
  final String unit;
  final List<String> sizeOptions;
  final List<String> colorOptions;
  final List<ProductVariantRecord> variantStocks;
  final bool allowPieceSale;
  final String pieceUnit;
  final double pieceQtyPerBase;
  final double piecePrice;

  factory ProductRecord.fromJson(Map<String, dynamic> json) {
    return ProductRecord(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      barcodeAliases: ((json['barcodeAliases'] as List?) ?? const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      productCode: _normalizeProductCode(
        json['productCode']?.toString(),
        json['barcode']?.toString(),
      ),
      gender: json['gender']?.toString() ?? '',
      category: ProductCategoryRef.fromJson(json['categoryId']),
      supplier: ProductSupplierRef.fromJson(json['supplierId']),
      purchasePrice: _toDouble(json['purchasePrice']),
      priceCurrency: json['priceCurrency']?.toString() == 'usd' ? 'usd' : 'uzs',
      usdRateUsed: _toDouble(json['usdRateUsed']),
      totalPurchaseCost: _toDouble(json['totalPurchaseCost']),
      retailPrice: _toDouble(json['retailPrice']),
      wholesalePrice: _toDouble(json['wholesalePrice']),
      paymentType: json['paymentType']?.toString() ?? 'naqd',
      paidAmount: _toDouble(json['paidAmount']),
      debtAmount: _toDouble(json['debtAmount']),
      quantity: _toDouble(json['quantity']),
      unit: json['unit']?.toString() ?? 'dona',
      sizeOptions: ((json['sizeOptions'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      colorOptions: ((json['colorOptions'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      variantStocks: ((json['variantStocks'] as List?) ?? const [])
          .map((item) => ProductVariantRecord.fromJson(item))
          .where((item) => item.size.isNotEmpty && item.color.isNotEmpty)
          .toList(),
      allowPieceSale: json['allowPieceSale'] == true,
      pieceUnit: json['pieceUnit']?.toString() ?? 'kg',
      pieceQtyPerBase: _toDouble(json['pieceQtyPerBase']),
      piecePrice: _toDouble(json['piecePrice']),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _normalizeProductCode(String? value, String? barcode) {
  final direct = (value ?? '').replaceAll(RegExp(r'\D+'), '');
  if (direct.isNotEmpty) {
    return direct.padLeft(4, '0').substring(direct.length >= 4 ? direct.length - 4 : 0);
  }
  final fallback = (barcode ?? '').replaceAll(RegExp(r'\D+'), '');
  if (fallback.isNotEmpty) {
    final last = fallback.length > 4 ? fallback.substring(fallback.length - 4) : fallback;
    return last.padLeft(4, '0');
  }
  return '0000';
}
