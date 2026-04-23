class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.amount,
    required this.reason,
    required this.spentAt,
  });

  final String id;
  final double amount;
  final String reason;
  final DateTime spentAt;

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord(
      id: json['_id']?.toString() ?? '',
      amount: _toDouble(json['amount']),
      reason: json['reason']?.toString() ?? '',
      spentAt: DateTime.tryParse(json['spentAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
