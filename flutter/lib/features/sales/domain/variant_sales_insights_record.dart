class VariantInsightTopRecord {
  const VariantInsightTopRecord({required this.label, required this.quantity});

  final String label;
  final double quantity;

  factory VariantInsightTopRecord.fromJson(Map<String, dynamic>? json) {
    return VariantInsightTopRecord(
      label: json?['label']?.toString() ?? '',
      quantity: _toDouble(json?['quantity']),
    );
  }
}

class VariantInsightRowRecord {
  const VariantInsightRowRecord({
    required this.productId,
    required this.productName,
    required this.size,
    required this.color,
    required this.quantity,
    required this.revenue,
  });

  final String productId;
  final String productName;
  final String size;
  final String color;
  final double quantity;
  final double revenue;

  factory VariantInsightRowRecord.fromJson(Map<String, dynamic> json) {
    return VariantInsightRowRecord(
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      size: json['size']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      quantity: _toDouble(json['quantity']),
      revenue: _toDouble(json['revenue']),
    );
  }
}

class VariantInsightsSummaryRecord {
  const VariantInsightsSummaryRecord({
    required this.totalQuantity,
    required this.totalRevenue,
    required this.topProduct,
    required this.topSize,
    required this.topColor,
  });

  final double totalQuantity;
  final double totalRevenue;
  final VariantInsightTopRecord topProduct;
  final VariantInsightTopRecord topSize;
  final VariantInsightTopRecord topColor;

  factory VariantInsightsSummaryRecord.fromJson(Map<String, dynamic>? json) {
    final rawTopProduct = _asMap(json?['topProduct']);
    final rawTopSize = _asMap(json?['topSize']);
    final rawTopColor = _asMap(json?['topColor']);
    return VariantInsightsSummaryRecord(
      totalQuantity: _toDouble(json?['totalQuantity']),
      totalRevenue: _toDouble(json?['totalRevenue']),
      topProduct: VariantInsightTopRecord.fromJson(rawTopProduct),
      topSize: VariantInsightTopRecord.fromJson(rawTopSize),
      topColor: VariantInsightTopRecord.fromJson(rawTopColor),
    );
  }
}

class VariantSalesInsightsRecord {
  const VariantSalesInsightsRecord({
    required this.summary,
    required this.availableSizes,
    required this.availableColors,
    required this.rows,
  });

  final VariantInsightsSummaryRecord summary;
  final List<String> availableSizes;
  final List<String> availableColors;
  final List<VariantInsightRowRecord> rows;

  factory VariantSalesInsightsRecord.fromJson(Map<String, dynamic> json) {
    final rawRows = (json['rows'] as List?) ?? const [];
    final rawSizes = (json['availableSizes'] as List?) ?? const [];
    final rawColors = (json['availableColors'] as List?) ?? const [];
    return VariantSalesInsightsRecord(
      summary: VariantInsightsSummaryRecord.fromJson(
        json['summary'] is Map<String, dynamic>
            ? json['summary'] as Map<String, dynamic>
            : json['summary'] is Map
            ? Map<String, dynamic>.from(json['summary'] as Map)
            : null,
      ),
      availableSizes: rawSizes.map((item) => item.toString()).toList(),
      availableColors: rawColors.map((item) => item.toString()).toList(),
      rows: rawRows
          .map(
            (item) => VariantInsightRowRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    );
  }

  factory VariantSalesInsightsRecord.empty() {
    return const VariantSalesInsightsRecord(
      summary: VariantInsightsSummaryRecord(
        totalQuantity: 0,
        totalRevenue: 0,
        topProduct: VariantInsightTopRecord(label: '', quantity: 0),
        topSize: VariantInsightTopRecord(label: '', quantity: 0),
        topColor: VariantInsightTopRecord(label: '', quantity: 0),
      ),
      availableSizes: [],
      availableColors: [],
      rows: [],
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}
