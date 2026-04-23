class SupplierStats {
  const SupplierStats({
    required this.totalPurchase,
    required this.totalPaid,
    required this.totalDebt,
    required this.totalPurchaseUsd,
    required this.totalPaidUsd,
    required this.totalDebtUsd,
  });

  final double totalPurchase;
  final double totalPaid;
  final double totalDebt;
  final double totalPurchaseUsd;
  final double totalPaidUsd;
  final double totalDebtUsd;

  factory SupplierStats.fromJson(Map<String, dynamic>? json) {
    return SupplierStats(
      totalPurchase: _toDouble(json?['totalPurchase']),
      totalPaid: _toDouble(json?['totalPaid']),
      totalDebt: _toDouble(json?['totalDebt']),
      totalPurchaseUsd: _toDouble(json?['totalPurchaseUsd']),
      totalPaidUsd: _toDouble(json?['totalPaidUsd']),
      totalDebtUsd: _toDouble(json?['totalDebtUsd']),
    );
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SupplierRecord {
  const SupplierRecord({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.stats,
  });

  final String id;
  final String name;
  final String address;
  final String phone;
  final SupplierStats stats;

  factory SupplierRecord.fromJson(Map<String, dynamic> json) {
    return SupplierRecord(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      stats: SupplierStats.fromJson(
        json['stats'] is Map<String, dynamic>
            ? json['stats'] as Map<String, dynamic>
            : json['stats'] is Map
            ? Map<String, dynamic>.from(json['stats'] as Map)
            : null,
      ),
    );
  }
}

class SupplierPurchaseRecord {
  const SupplierPurchaseRecord({
    required this.id,
    required this.purchasedAt,
    required this.productName,
    required this.productModel,
    required this.quantity,
    required this.unit,
    required this.totalCost,
    required this.paidAmount,
    required this.debtAmount,
    required this.paymentType,
  });

  final String id;
  final DateTime? purchasedAt;
  final String productName;
  final String productModel;
  final double quantity;
  final String unit;
  final double totalCost;
  final double paidAmount;
  final double debtAmount;
  final String paymentType;

  factory SupplierPurchaseRecord.fromJson(Map<String, dynamic> json) {
    return SupplierPurchaseRecord(
      id: json['_id']?.toString() ?? '',
      purchasedAt: DateTime.tryParse(json['purchasedAt']?.toString() ?? ''),
      productName: json['productName']?.toString() ?? '',
      productModel: json['productModel']?.toString() ?? '',
      quantity: SupplierStats._toDouble(json['quantity']),
      unit: json['unit']?.toString() ?? '',
      totalCost: SupplierStats._toDouble(json['totalCost']),
      paidAmount: SupplierStats._toDouble(json['paidAmount']),
      debtAmount: SupplierStats._toDouble(json['debtAmount']),
      paymentType: json['paymentType']?.toString() ?? '',
    );
  }
}

class SupplierPaymentRecord {
  const SupplierPaymentRecord({
    required this.id,
    required this.paidAt,
    required this.amount,
    required this.note,
  });

  final String id;
  final DateTime? paidAt;
  final double amount;
  final String note;

  factory SupplierPaymentRecord.fromJson(Map<String, dynamic> json) {
    return SupplierPaymentRecord(
      id: json['_id']?.toString() ?? '',
      paidAt: DateTime.tryParse(json['paidAt']?.toString() ?? ''),
      amount: SupplierStats._toDouble(json['amount']),
      note: json['note']?.toString() ?? '',
    );
  }
}

class SupplierLedgerTotalsRecord {
  const SupplierLedgerTotalsRecord({
    required this.totalPurchase,
    required this.totalPaid,
    required this.totalDebt,
    required this.totalPurchaseUsd,
    required this.totalPaidUsd,
    required this.totalDebtUsd,
  });

  final double totalPurchase;
  final double totalPaid;
  final double totalDebt;
  final double totalPurchaseUsd;
  final double totalPaidUsd;
  final double totalDebtUsd;

  factory SupplierLedgerTotalsRecord.fromJson(Map<String, dynamic>? json) {
    return SupplierLedgerTotalsRecord(
      totalPurchase: SupplierStats._toDouble(json?['totalPurchase']),
      totalPaid: SupplierStats._toDouble(json?['totalPaid']),
      totalDebt: SupplierStats._toDouble(json?['totalDebt']),
      totalPurchaseUsd: SupplierStats._toDouble(json?['totalPurchaseUsd']),
      totalPaidUsd: SupplierStats._toDouble(json?['totalPaidUsd']),
      totalDebtUsd: SupplierStats._toDouble(json?['totalDebtUsd']),
    );
  }
}

class SupplierLedgerRecord {
  const SupplierLedgerRecord({
    required this.supplier,
    required this.purchases,
    required this.payments,
    required this.totals,
  });

  final SupplierRecord supplier;
  final List<SupplierPurchaseRecord> purchases;
  final List<SupplierPaymentRecord> payments;
  final SupplierLedgerTotalsRecord totals;

  factory SupplierLedgerRecord.fromJson(Map<String, dynamic> json) {
    final rawPurchases = (json['purchases'] as List?) ?? const [];
    final rawPayments = (json['payments'] as List?) ?? const [];
    return SupplierLedgerRecord(
      supplier: SupplierRecord.fromJson(
        json['supplier'] is Map<String, dynamic>
            ? json['supplier'] as Map<String, dynamic>
            : Map<String, dynamic>.from(json['supplier'] as Map),
      ),
      purchases: rawPurchases
          .map(
            (item) => SupplierPurchaseRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      payments: rawPayments
          .map(
            (item) => SupplierPaymentRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      totals: SupplierLedgerTotalsRecord.fromJson(
        json['totals'] is Map<String, dynamic>
            ? json['totals'] as Map<String, dynamic>
            : json['totals'] is Map
            ? Map<String, dynamic>.from(json['totals'] as Map)
            : null,
      ),
    );
  }
}
