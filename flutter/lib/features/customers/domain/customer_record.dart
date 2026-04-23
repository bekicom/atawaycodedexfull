class CustomersSummaryRecord {
  const CustomersSummaryRecord({
    required this.totalCustomers,
    required this.activeDebtors,
    required this.totalDebt,
    required this.totalPaid,
  });

  final int totalCustomers;
  final int activeDebtors;
  final double totalDebt;
  final double totalPaid;

  factory CustomersSummaryRecord.fromJson(Map<String, dynamic>? json) {
    return CustomersSummaryRecord(
      totalCustomers: (json?['totalCustomers'] as num?)?.toInt() ?? 0,
      activeDebtors: (json?['activeDebtors'] as num?)?.toInt() ?? 0,
      totalDebt: _toDouble(json?['totalDebt']),
      totalPaid: _toDouble(json?['totalPaid']),
    );
  }
}

class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.totalDebt,
    required this.totalPaid,
  });

  final String id;
  final String fullName;
  final String phone;
  final String address;
  final double totalDebt;
  final double totalPaid;

  factory CustomerRecord.fromJson(Map<String, dynamic> json) {
    return CustomerRecord(
      id: json['_id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      totalDebt: _toDouble(json['totalDebt']),
      totalPaid: _toDouble(json['totalPaid']),
    );
  }
}

class CustomersListRecord {
  const CustomersListRecord({
    required this.customers,
    required this.summary,
  });

  final List<CustomerRecord> customers;
  final CustomersSummaryRecord summary;

  factory CustomersListRecord.fromJson(Map<String, dynamic> json) {
    final rawCustomers = (json['customers'] as List?) ?? const [];
    return CustomersListRecord(
      customers: rawCustomers
          .map((item) => CustomerRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      summary: CustomersSummaryRecord.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
                ? Map<String, dynamic>.from(json['summary'] as Map)
                : null,
      ),
    );
  }
}

class CustomerLedgerSaleRecord {
  const CustomerLedgerSaleRecord({
    required this.id,
    required this.createdAt,
    required this.totalAmount,
    required this.debtAmount,
    required this.note,
    required this.items,
  });

  final String id;
  final DateTime? createdAt;
  final double totalAmount;
  final double debtAmount;
  final String note;
  final List<CustomerLedgerSaleItemRecord> items;

  factory CustomerLedgerSaleRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return CustomerLedgerSaleRecord(
      id: json['_id']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      totalAmount: _toDouble(json['totalAmount']),
      debtAmount: _toDouble(json['debtAmount']),
      note: json['note']?.toString() ?? '',
      items: rawItems
          .map((item) => CustomerLedgerSaleItemRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class CustomerLedgerSaleItemRecord {
  const CustomerLedgerSaleItemRecord({
    required this.productName,
    required this.productModel,
    required this.quantity,
    required this.unit,
  });

  final String productName;
  final String productModel;
  final double quantity;
  final String unit;

  factory CustomerLedgerSaleItemRecord.fromJson(Map<String, dynamic> json) {
    return CustomerLedgerSaleItemRecord(
      productName: json['productName']?.toString() ?? '',
      productModel: json['productModel']?.toString() ?? '',
      quantity: _toDouble(json['quantity']),
      unit: json['unit']?.toString() ?? '',
    );
  }
}

class CustomerPaymentRecord {
  const CustomerPaymentRecord({
    required this.id,
    required this.paidAt,
    required this.amount,
    required this.cashierUsername,
    required this.note,
  });

  final String id;
  final DateTime? paidAt;
  final double amount;
  final String cashierUsername;
  final String note;

  factory CustomerPaymentRecord.fromJson(Map<String, dynamic> json) {
    return CustomerPaymentRecord(
      id: json['_id']?.toString() ?? '',
      paidAt: DateTime.tryParse(json['paidAt']?.toString() ?? ''),
      amount: _toDouble(json['amount']),
      cashierUsername: json['cashierUsername']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
    );
  }
}

class CustomerLedgerTotalsRecord {
  const CustomerLedgerTotalsRecord({
    required this.totalSalesAmount,
    required this.totalDebt,
    required this.totalPaid,
  });

  final double totalSalesAmount;
  final double totalDebt;
  final double totalPaid;

  factory CustomerLedgerTotalsRecord.fromJson(Map<String, dynamic>? json) {
    return CustomerLedgerTotalsRecord(
      totalSalesAmount: _toDouble(json?['totalSalesAmount']),
      totalDebt: _toDouble(json?['totalDebt']),
      totalPaid: _toDouble(json?['totalPaid']),
    );
  }
}

class CustomerLedgerRecord {
  const CustomerLedgerRecord({
    required this.customer,
    required this.sales,
    required this.payments,
    required this.totals,
  });

  final CustomerRecord customer;
  final List<CustomerLedgerSaleRecord> sales;
  final List<CustomerPaymentRecord> payments;
  final CustomerLedgerTotalsRecord totals;

  factory CustomerLedgerRecord.fromJson(Map<String, dynamic> json) {
    final rawSales = (json['sales'] as List?) ?? const [];
    final rawPayments = (json['payments'] as List?) ?? const [];
    return CustomerLedgerRecord(
      customer: CustomerRecord.fromJson(
        json['customer'] is Map<String, dynamic>
            ? json['customer'] as Map<String, dynamic>
            : Map<String, dynamic>.from(json['customer'] as Map),
      ),
      sales: rawSales
          .map((item) => CustomerLedgerSaleRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      payments: rawPayments
          .map((item) => CustomerPaymentRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      totals: CustomerLedgerTotalsRecord.fromJson(
        json['totals'] is Map<String, dynamic>
            ? json['totals'] as Map<String, dynamic>
            : json['totals'] is Map
                ? Map<String, dynamic>.from(json['totals'] as Map)
                : null,
      ),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
