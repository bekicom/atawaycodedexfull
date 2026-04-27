class SalePaymentsRecord {
  const SalePaymentsRecord({
    required this.cash,
    required this.card,
    required this.click,
  });

  final double cash;
  final double card;
  final double click;

  factory SalePaymentsRecord.fromJson(Map<String, dynamic>? json) {
    return SalePaymentsRecord(
      cash: _toDouble(json?['cash']),
      card: _toDouble(json?['card']),
      click: _toDouble(json?['click']),
    );
  }
}

class SaleItemRecord {
  const SaleItemRecord({
    required this.productId,
    required this.productName,
    required this.productModel,
    required this.categoryName,
    required this.barcode,
    required this.productCode,
    required this.variantSize,
    required this.variantColor,
    required this.quantity,
    required this.returnedQuantity,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
    required this.returnedTotal,
    required this.lineProfit,
    required this.returnedProfit,
  });

  final String productId;
  final String productName;
  final String productModel;
  final String categoryName;
  final String barcode;
  final String productCode;
  final String variantSize;
  final String variantColor;
  final double quantity;
  final double returnedQuantity;
  final String unit;
  final double unitPrice;
  final double lineTotal;
  final double returnedTotal;
  final double lineProfit;
  final double returnedProfit;

  double get availableQuantity => quantity - returnedQuantity;
  bool get isFullyReturned => availableQuantity <= 0.0001;

  factory SaleItemRecord.fromJson(Map<String, dynamic> json) {
    return SaleItemRecord(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productModel: json['productModel']?.toString() ?? '',
      categoryName: json['categoryName']?.toString() ?? '',
      barcode: json['barcode']?.toString() ?? '',
      productCode: _normalizeProductCode(
        json['productCode']?.toString(),
        json['productModel']?.toString(),
        json['barcode']?.toString(),
      ),
      variantSize: json['variantSize']?.toString() ?? '',
      variantColor: json['variantColor']?.toString() ?? '',
      quantity: _toDouble(json['quantity']),
      returnedQuantity: _toDouble(json['returnedQuantity']),
      unit: json['unit']?.toString() ?? '',
      unitPrice: _toDouble(json['unitPrice']),
      lineTotal: _toDouble(json['lineTotal']),
      returnedTotal: _toDouble(json['returnedTotal']),
      lineProfit: _toDouble(json['lineProfit']),
      returnedProfit: _toDouble(json['returnedProfit']),
    );
  }
}

class SaleReturnRecord {
  const SaleReturnRecord({
    required this.id,
    required this.createdAt,
    required this.cashierUsername,
    required this.shiftId,
    required this.shiftNumber,
    required this.paymentType,
    required this.payments,
    required this.totalAmount,
  });

  final String id;
  final DateTime? createdAt;
  final String cashierUsername;
  final String shiftId;
  final int shiftNumber;
  final String paymentType;
  final SalePaymentsRecord payments;
  final double totalAmount;

  factory SaleReturnRecord.fromJson(Map<String, dynamic> json) {
    return SaleReturnRecord(
      id: json['_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      cashierUsername: json['cashierUsername']?.toString() ?? '',
      shiftId: json['shiftId']?.toString() ?? '',
      shiftNumber: (json['shiftNumber'] as num?)?.toInt() ?? 0,
      paymentType: json['paymentType']?.toString() ?? '',
      payments: SalePaymentsRecord.fromJson(
        json['payments'] is Map<String, dynamic>
            ? json['payments'] as Map<String, dynamic>
            : json['payments'] is Map
            ? Map<String, dynamic>.from(json['payments'] as Map)
            : null,
      ),
      totalAmount: _toDouble(json['totalAmount']),
    );
  }
}

class SaleRecord {
  const SaleRecord({
    required this.id,
    required this.saleNumber,
    required this.transactionType,
    required this.createdAt,
    required this.cashierUsername,
    required this.shiftId,
    required this.shiftNumber,
    required this.shiftOpenedAt,
    required this.paymentType,
    required this.payments,
    required this.returnedPayments,
    required this.totalAmount,
    required this.returnedAmount,
    required this.debtAmount,
    required this.customerName,
    required this.note,
    required this.items,
    required this.returns,
  });

  final String id;
  final int saleNumber;
  final String transactionType;
  final DateTime? createdAt;
  final String cashierUsername;
  final String shiftId;
  final int shiftNumber;
  final DateTime? shiftOpenedAt;
  final String paymentType;
  final SalePaymentsRecord payments;
  final SalePaymentsRecord returnedPayments;
  final double totalAmount;
  final double returnedAmount;
  final double debtAmount;
  final String customerName;
  final String note;
  final List<SaleItemRecord> items;
  final List<SaleReturnRecord> returns;

  bool get hasReturn =>
      returnedAmount > 0.0001 ||
      items.any((item) => item.returnedQuantity > 0.0001);
  String get receiptNumber => saleNumber > 0
      ? saleNumber.toString().padLeft(6, '0')
      : _fallbackReceiptNumber(id);

  factory SaleRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return SaleRecord(
      id: json['_id']?.toString() ?? '',
      saleNumber: (json['saleNumber'] as num?)?.toInt() ?? 0,
      transactionType: json['transactionType']?.toString() ?? 'sale',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      cashierUsername: json['cashierUsername']?.toString() ?? '-',
      shiftId: json['shiftId']?.toString() ?? '',
      shiftNumber: (json['shiftNumber'] as num?)?.toInt() ?? 0,
      shiftOpenedAt: DateTime.tryParse(json['shiftOpenedAt']?.toString() ?? ''),
      paymentType: json['paymentType']?.toString() ?? '',
      payments: SalePaymentsRecord.fromJson(
        json['payments'] is Map<String, dynamic>
            ? json['payments'] as Map<String, dynamic>
            : json['payments'] is Map
            ? Map<String, dynamic>.from(json['payments'] as Map)
            : null,
      ),
      returnedPayments: SalePaymentsRecord.fromJson(
        json['returnedPayments'] is Map<String, dynamic>
            ? json['returnedPayments'] as Map<String, dynamic>
            : json['returnedPayments'] is Map
            ? Map<String, dynamic>.from(json['returnedPayments'] as Map)
            : null,
      ),
      totalAmount: _toDouble(json['totalAmount']),
      returnedAmount: _toDouble(json['returnedAmount']),
      debtAmount: _toDouble(json['debtAmount']),
      customerName: json['customerName']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      items: rawItems
          .map(
            (item) =>
                SaleItemRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      returns: ((json['returns'] as List?) ?? const [])
          .map(
            (item) => SaleReturnRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class SalesSummaryRecord {
  const SalesSummaryRecord({
    required this.totalSales,
    required this.totalCollection,
    required this.totalDebtPayment,
    required this.totalCard,
    required this.totalCash,
    required this.totalClick,
    required this.totalRevenue,
    required this.totalProfit,
    required this.totalExpense,
  });

  final int totalSales;
  final double totalCollection;
  final double totalDebtPayment;
  final double totalCard;
  final double totalCash;
  final double totalClick;
  final double totalRevenue;
  final double totalProfit;
  final double totalExpense;

  factory SalesSummaryRecord.fromJson(Map<String, dynamic>? json) {
    return SalesSummaryRecord(
      totalSales: (json?['totalSales'] as num?)?.toInt() ?? 0,
      totalCollection: _toDouble(json?['totalCollection']),
      totalDebtPayment: _toDouble(json?['totalDebtPayment']),
      totalCard: _toDouble(json?['totalCard']),
      totalCash: _toDouble(json?['totalCash']),
      totalClick: _toDouble(json?['totalClick']),
      totalRevenue: _toDouble(json?['totalRevenue']),
      totalProfit: _toDouble(json?['totalProfit']),
      totalExpense: _toDouble(json?['totalExpense']),
    );
  }
}

class SalesHistoryRecord {
  const SalesHistoryRecord({required this.sales, required this.summary});

  final List<SaleRecord> sales;
  final SalesSummaryRecord summary;

  factory SalesHistoryRecord.fromJson(Map<String, dynamic> json) {
    final rawSales = (json['sales'] as List?) ?? const [];
    return SalesHistoryRecord(
      sales: rawSales
          .map(
            (item) =>
                SaleRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      summary: SalesSummaryRecord.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : null,
      ),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _normalizeProductCode(String? value, String? model, String? barcode) {
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

String _fallbackReceiptNumber(String value) {
  final digits = value.replaceAll(RegExp(r'\D+'), '');
  if (digits.isNotEmpty) {
    final last = digits.length > 6
        ? digits.substring(digits.length - 6)
        : digits;
    return last.padLeft(4, '0');
  }

  final normalized = value.trim();
  if (normalized.isEmpty) return '1000';

  var hash = 0;
  for (final unit in normalized.codeUnits) {
    hash = (hash * 31 + unit) % 900000;
  }
  final number = 1000 + hash;
  return number.toString().padLeft(4, '0');
}
