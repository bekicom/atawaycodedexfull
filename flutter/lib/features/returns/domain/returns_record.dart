class ReturnPaymentsRecord {
  const ReturnPaymentsRecord({
    required this.cash,
    required this.card,
    required this.click,
  });

  final double cash;
  final double card;
  final double click;

  factory ReturnPaymentsRecord.fromJson(Map<String, dynamic>? json) {
    return ReturnPaymentsRecord(
      cash: _toDouble(json?['cash']),
      card: _toDouble(json?['card']),
      click: _toDouble(json?['click']),
    );
  }
}

class ReturnItemRecord {
  const ReturnItemRecord({
    required this.productName,
    required this.quantity,
    required this.unit,
  });

  final String productName;
  final double quantity;
  final String unit;

  factory ReturnItemRecord.fromJson(Map<String, dynamic> json) {
    return ReturnItemRecord(
      productName: json['productName']?.toString() ?? '',
      quantity: _toDouble(json['quantity']),
      unit: json['unit']?.toString() ?? '',
    );
  }
}

class ReturnRecord {
  const ReturnRecord({
    required this.id,
    required this.saleId,
    required this.saleCreatedAt,
    required this.returnCreatedAt,
    required this.cashierUsername,
    required this.shiftId,
    required this.shiftNumber,
    required this.paymentType,
    required this.payments,
    required this.totalAmount,
    required this.note,
    required this.items,
  });

  final String id;
  final String saleId;
  final DateTime? saleCreatedAt;
  final DateTime? returnCreatedAt;
  final String cashierUsername;
  final String shiftId;
  final int shiftNumber;
  final String paymentType;
  final ReturnPaymentsRecord payments;
  final double totalAmount;
  final String note;
  final List<ReturnItemRecord> items;

  factory ReturnRecord.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return ReturnRecord(
      id: json['_id']?.toString() ?? '',
      saleId: json['saleId']?.toString() ?? '',
      saleCreatedAt: DateTime.tryParse(json['saleCreatedAt']?.toString() ?? ''),
      returnCreatedAt: DateTime.tryParse(
        json['returnCreatedAt']?.toString() ?? '',
      ),
      cashierUsername: json['cashierUsername']?.toString() ?? '-',
      shiftId: json['shiftId']?.toString() ?? '',
      shiftNumber: (json['shiftNumber'] as num?)?.toInt() ?? 0,
      paymentType: json['paymentType']?.toString() ?? '',
      payments: ReturnPaymentsRecord.fromJson(
        json['payments'] is Map<String, dynamic>
            ? json['payments'] as Map<String, dynamic>
            : json['payments'] is Map
            ? Map<String, dynamic>.from(json['payments'] as Map)
            : null,
      ),
      totalAmount: _toDouble(json['totalAmount']),
      note: json['note']?.toString() ?? '',
      items: rawItems
          .map(
            (item) => ReturnItemRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }
}

class ReturnsSummaryRecord {
  const ReturnsSummaryRecord({
    required this.totalReturns,
    required this.totalReturnedAmount,
    required this.totalReturnedCash,
    required this.totalReturnedCard,
    required this.totalReturnedClick,
    required this.totalReturnedQty,
  });

  final int totalReturns;
  final double totalReturnedAmount;
  final double totalReturnedCash;
  final double totalReturnedCard;
  final double totalReturnedClick;
  final double totalReturnedQty;

  factory ReturnsSummaryRecord.fromJson(Map<String, dynamic>? json) {
    return ReturnsSummaryRecord(
      totalReturns: (json?['totalReturns'] as num?)?.toInt() ?? 0,
      totalReturnedAmount: _toDouble(json?['totalReturnedAmount']),
      totalReturnedCash: _toDouble(json?['totalReturnedCash']),
      totalReturnedCard: _toDouble(json?['totalReturnedCard']),
      totalReturnedClick: _toDouble(json?['totalReturnedClick']),
      totalReturnedQty: _toDouble(json?['totalReturnedQty']),
    );
  }
}

class ReturnsRecord {
  const ReturnsRecord({required this.returns, required this.summary});

  final List<ReturnRecord> returns;
  final ReturnsSummaryRecord summary;

  factory ReturnsRecord.fromJson(Map<String, dynamic> json) {
    final rawReturns = (json['returns'] as List?) ?? const [];
    return ReturnsRecord(
      returns: rawReturns
          .map(
            (item) =>
                ReturnRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      summary: ReturnsSummaryRecord.fromJson(
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
