class ShiftRecord {
  const ShiftRecord({
    required this.id,
    required this.cashierId,
    required this.cashierUsername,
    required this.shiftNumber,
    required this.status,
    required this.openedAt,
    required this.closedAt,
    required this.totalSalesCount,
    required this.totalItemsCount,
    required this.totalAmount,
    required this.totalCash,
    required this.totalCard,
    required this.totalClick,
    required this.totalDebt,
    required this.lastSaleAt,
  });

  final String id;
  final String cashierId;
  final String cashierUsername;
  final int shiftNumber;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final int totalSalesCount;
  final double totalItemsCount;
  final double totalAmount;
  final double totalCash;
  final double totalCard;
  final double totalClick;
  final double totalDebt;
  final DateTime? lastSaleAt;

  bool get isOpen => status == 'open';

  factory ShiftRecord.fromJson(Map<String, dynamic> json) {
    return ShiftRecord(
      id: json['_id']?.toString() ?? '',
      cashierId: json['cashierId']?.toString() ?? '',
      cashierUsername: json['cashierUsername']?.toString() ?? '',
      shiftNumber: (json['shiftNumber'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'closed',
      openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? ''),
      closedAt: DateTime.tryParse(json['closedAt']?.toString() ?? ''),
      totalSalesCount: (json['totalSalesCount'] as num?)?.toInt() ?? 0,
      totalItemsCount: _toDouble(json['totalItemsCount']),
      totalAmount: _toDouble(json['totalAmount']),
      totalCash: _toDouble(json['totalCash']),
      totalCard: _toDouble(json['totalCard']),
      totalClick: _toDouble(json['totalClick']),
      totalDebt: _toDouble(json['totalDebt']),
      lastSaleAt: DateTime.tryParse(json['lastSaleAt']?.toString() ?? ''),
    );
  }
}

class ShiftSummaryRecord {
  const ShiftSummaryRecord({
    required this.totalShifts,
    required this.openShifts,
    required this.closedShifts,
    required this.totalSalesCount,
    required this.totalAmount,
    required this.totalCash,
    required this.totalCard,
    required this.totalClick,
    required this.totalDebt,
  });

  final int totalShifts;
  final int openShifts;
  final int closedShifts;
  final int totalSalesCount;
  final double totalAmount;
  final double totalCash;
  final double totalCard;
  final double totalClick;
  final double totalDebt;

  factory ShiftSummaryRecord.fromJson(Map<String, dynamic>? json) {
    return ShiftSummaryRecord(
      totalShifts: (json?['totalShifts'] as num?)?.toInt() ?? 0,
      openShifts: (json?['openShifts'] as num?)?.toInt() ?? 0,
      closedShifts: (json?['closedShifts'] as num?)?.toInt() ?? 0,
      totalSalesCount: (json?['totalSalesCount'] as num?)?.toInt() ?? 0,
      totalAmount: _toDouble(json?['totalAmount']),
      totalCash: _toDouble(json?['totalCash']),
      totalCard: _toDouble(json?['totalCard']),
      totalClick: _toDouble(json?['totalClick']),
      totalDebt: _toDouble(json?['totalDebt']),
    );
  }
}

class ShiftsListRecord {
  const ShiftsListRecord({required this.shifts, required this.summary});

  final List<ShiftRecord> shifts;
  final ShiftSummaryRecord summary;

  factory ShiftsListRecord.fromJson(Map<String, dynamic> json) {
    final rawShifts = (json['shifts'] as List?) ?? const [];
    return ShiftsListRecord(
      shifts: rawShifts
          .map(
            (item) =>
                ShiftRecord.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      summary: ShiftSummaryRecord.fromJson(
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
