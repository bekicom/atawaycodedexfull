class ReceiptFieldsRecord {
  const ReceiptFieldsRecord({
    required this.showLogo,
    required this.showTitle,
    required this.showReceiptNumber,
    required this.showDate,
    required this.showTime,
    required this.showType,
    required this.showShift,
    required this.showCashier,
    required this.showPaymentType,
    required this.showCustomer,
    required this.showItemsTable,
    required this.showItemUnitPrice,
    required this.showItemLineTotal,
    required this.showTotal,
    required this.showFooter,
    required this.showLegalText,
    required this.showPhoneNumber,
    required this.showContactLine,
  });

  final bool showLogo;
  final bool showTitle;
  final bool showReceiptNumber;
  final bool showDate;
  final bool showTime;
  final bool showType;
  final bool showShift;
  final bool showCashier;
  final bool showPaymentType;
  final bool showCustomer;
  final bool showItemsTable;
  final bool showItemUnitPrice;
  final bool showItemLineTotal;
  final bool showTotal;
  final bool showFooter;
  final bool showLegalText;
  final bool showPhoneNumber;
  final bool showContactLine;

  factory ReceiptFieldsRecord.fromJson(Map<String, dynamic>? json) {
    return ReceiptFieldsRecord(
      showLogo: json?['showLogo'] != false,
      showTitle: json?['showTitle'] != false,
      showReceiptNumber: json?['showReceiptNumber'] != false,
      showDate: json?['showDate'] != false,
      showTime: json?['showTime'] != false,
      showType: json?['showType'] == true,
      showShift: json?['showShift'] != false,
      showCashier: json?['showCashier'] != false,
      showPaymentType: json?['showPaymentType'] != false,
      showCustomer: json?['showCustomer'] != false,
      showItemsTable: json?['showItemsTable'] != false,
      showItemUnitPrice: json?['showItemUnitPrice'] != false,
      showItemLineTotal: json?['showItemLineTotal'] != false,
      showTotal: json?['showTotal'] != false,
      showFooter: json?['showFooter'] != false,
      showLegalText: json?['showLegalText'] != false,
      showPhoneNumber: json?['showPhoneNumber'] != false,
      showContactLine: json?['showContactLine'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showLogo': showLogo,
      'showTitle': showTitle,
      'showReceiptNumber': showReceiptNumber,
      'showDate': showDate,
      'showTime': showTime,
      'showType': showType,
      'showShift': showShift,
      'showCashier': showCashier,
      'showPaymentType': showPaymentType,
      'showCustomer': showCustomer,
      'showItemsTable': showItemsTable,
      'showItemUnitPrice': showItemUnitPrice,
      'showItemLineTotal': showItemLineTotal,
      'showTotal': showTotal,
      'showFooter': showFooter,
      'showLegalText': showLegalText,
      'showPhoneNumber': showPhoneNumber,
      'showContactLine': showContactLine,
    };
  }

  ReceiptFieldsRecord copyWith({
    bool? showLogo,
    bool? showTitle,
    bool? showReceiptNumber,
    bool? showDate,
    bool? showTime,
    bool? showType,
    bool? showShift,
    bool? showCashier,
    bool? showPaymentType,
    bool? showCustomer,
    bool? showItemsTable,
    bool? showItemUnitPrice,
    bool? showItemLineTotal,
    bool? showTotal,
    bool? showFooter,
    bool? showLegalText,
    bool? showPhoneNumber,
    bool? showContactLine,
  }) {
    return ReceiptFieldsRecord(
      showLogo: showLogo ?? this.showLogo,
      showTitle: showTitle ?? this.showTitle,
      showReceiptNumber: showReceiptNumber ?? this.showReceiptNumber,
      showDate: showDate ?? this.showDate,
      showTime: showTime ?? this.showTime,
      showType: showType ?? this.showType,
      showShift: showShift ?? this.showShift,
      showCashier: showCashier ?? this.showCashier,
      showPaymentType: showPaymentType ?? this.showPaymentType,
      showCustomer: showCustomer ?? this.showCustomer,
      showItemsTable: showItemsTable ?? this.showItemsTable,
      showItemUnitPrice: showItemUnitPrice ?? this.showItemUnitPrice,
      showItemLineTotal: showItemLineTotal ?? this.showItemLineTotal,
      showTotal: showTotal ?? this.showTotal,
      showFooter: showFooter ?? this.showFooter,
      showLegalText: showLegalText ?? this.showLegalText,
      showPhoneNumber: showPhoneNumber ?? this.showPhoneNumber,
      showContactLine: showContactLine ?? this.showContactLine,
    );
  }
}

class ReceiptSettingsRecord {
  const ReceiptSettingsRecord({
    required this.title,
    required this.footer,
    required this.phoneNumber,
    required this.legalText,
    required this.contactLine,
    required this.logoUrl,
    required this.fields,
  });

  final String title;
  final String footer;
  final String phoneNumber;
  final String legalText;
  final String contactLine;
  final String logoUrl;
  final ReceiptFieldsRecord fields;

  factory ReceiptSettingsRecord.fromJson(Map<String, dynamic>? json) {
    final rawFields = json?['fields'];
    const defaultLegalText =
        'Hurmatli xaridor!\n'
        'Maxsulotni ilk holatdagi korinishi va qadogi buzulmagan muhri va yorliqlari mavjud bolsa 1 hafta ichida almashtirish huquqiga egasz.\n'
        'Almashtirishda mahsulot yorligi hamda xarid cheki talab qilinadi.\n'
        'Oyinchoqlar, aksessuarlar (surgich butilka), ichkiyimlar, suzish kiyimlari, chaqaloqlar kiyimlari gigiyenik nuqtai nazardan almashtirib berilmaydi.';
    return ReceiptSettingsRecord(
      title: json?['title']?.toString() ?? 'CHEK',
      footer: json?['footer']?.toString() ?? 'XARIDINGIZ UCHUN RAHMAT',
      phoneNumber: json?['phoneNumber']?.toString() ?? '',
      legalText: json?['legalText']?.toString() ?? defaultLegalText,
      contactLine: json?['contactLine']?.toString() ?? '',
      logoUrl: json?['logoUrl']?.toString() ?? '',
      fields: ReceiptFieldsRecord.fromJson(
        rawFields is Map<String, dynamic>
            ? rawFields
            : rawFields is Map
            ? Map<String, dynamic>.from(rawFields)
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'footer': footer,
      'phoneNumber': phoneNumber,
      'legalText': legalText,
      'contactLine': contactLine,
      'logoUrl': logoUrl,
      'fields': fields.toJson(),
    };
  }

  ReceiptSettingsRecord copyWith({
    String? title,
    String? footer,
    String? phoneNumber,
    String? legalText,
    String? contactLine,
    String? logoUrl,
    ReceiptFieldsRecord? fields,
  }) {
    return ReceiptSettingsRecord(
      title: title ?? this.title,
      footer: footer ?? this.footer,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      legalText: legalText ?? this.legalText,
      contactLine: contactLine ?? this.contactLine,
      logoUrl: logoUrl ?? this.logoUrl,
      fields: fields ?? this.fields,
    );
  }
}

class BarcodeLabelFieldsRecord {
  const BarcodeLabelFieldsRecord({
    required this.showName,
    required this.showBarcode,
    required this.showPrice,
    required this.showModel,
    required this.showCategory,
  });

  final bool showName;
  final bool showBarcode;
  final bool showPrice;
  final bool showModel;
  final bool showCategory;

  factory BarcodeLabelFieldsRecord.fromJson(Map<String, dynamic>? json) {
    return BarcodeLabelFieldsRecord(
      showName: json?['showName'] != false,
      showBarcode: json?['showBarcode'] != false,
      showPrice: json?['showPrice'] != false,
      showModel: json?['showModel'] != false,
      showCategory: json?['showCategory'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showName': showName,
      'showBarcode': showBarcode,
      'showPrice': showPrice,
      'showModel': showModel,
      'showCategory': showCategory,
    };
  }

  BarcodeLabelFieldsRecord copyWith({
    bool? showName,
    bool? showBarcode,
    bool? showPrice,
    bool? showModel,
    bool? showCategory,
  }) {
    return BarcodeLabelFieldsRecord(
      showName: showName ?? this.showName,
      showBarcode: showBarcode ?? this.showBarcode,
      showPrice: showPrice ?? this.showPrice,
      showModel: showModel ?? this.showModel,
      showCategory: showCategory ?? this.showCategory,
    );
  }
}

class BarcodeLabelSettingsRecord {
  const BarcodeLabelSettingsRecord({
    required this.paperSize,
    required this.orientation,
    required this.copies,
    required this.fields,
  });

  final String paperSize;
  final String orientation;
  final int copies;
  final BarcodeLabelFieldsRecord fields;

  factory BarcodeLabelSettingsRecord.fromJson(Map<String, dynamic>? json) {
    const supportedSizes = {'58x40', '60x40', '70x50', '80x50'};
    const supportedOrientations = {'portrait', 'landscape'};
    final rawSize = json?['paperSize']?.toString() ?? '58x40';
    final rawOrientation = json?['orientation']?.toString() ?? 'portrait';
    final rawCopies = (json?['copies'] as num?)?.toInt() ?? 1;
    final rawFields = json?['fields'];
    return BarcodeLabelSettingsRecord(
      paperSize: supportedSizes.contains(rawSize) ? rawSize : '58x40',
      orientation: supportedOrientations.contains(rawOrientation)
          ? rawOrientation
          : 'portrait',
      copies: rawCopies < 1 ? 1 : rawCopies,
      fields: BarcodeLabelFieldsRecord.fromJson(
        rawFields is Map<String, dynamic>
            ? rawFields
            : rawFields is Map
            ? Map<String, dynamic>.from(rawFields)
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'paperSize': paperSize,
      'orientation': orientation,
      'copies': copies,
      'fields': fields.toJson(),
    };
  }

  BarcodeLabelSettingsRecord copyWith({
    String? paperSize,
    String? orientation,
    int? copies,
    BarcodeLabelFieldsRecord? fields,
  }) {
    return BarcodeLabelSettingsRecord(
      paperSize: paperSize ?? this.paperSize,
      orientation: orientation ?? this.orientation,
      copies: copies ?? this.copies,
      fields: fields ?? this.fields,
    );
  }
}

class AppSettingsRecord {
  const AppSettingsRecord({
    required this.lowStockThreshold,
    required this.usdRate,
    required this.displayCurrency,
    required this.keyboardEnabled,
    required this.posCompactMode,
    required this.variantInsightsEnabled,
    required this.receipt,
    required this.barcodeLabel,
  });

  final int lowStockThreshold;
  final double usdRate;
  final String displayCurrency;
  final bool keyboardEnabled;
  final bool posCompactMode;
  final bool variantInsightsEnabled;
  final ReceiptSettingsRecord receipt;
  final BarcodeLabelSettingsRecord barcodeLabel;

  factory AppSettingsRecord.fromJson(Map<String, dynamic> json) {
    final rawReceipt = json['receipt'];
    final rawBarcodeLabel = json['barcodeLabel'];
    return AppSettingsRecord(
      lowStockThreshold: (json['lowStockThreshold'] as num?)?.toInt() ?? 5,
      usdRate: (json['usdRate'] as num?)?.toDouble() ?? 12171,
      displayCurrency: json['displayCurrency']?.toString() == 'usd'
          ? 'usd'
          : 'uzs',
      keyboardEnabled: json['keyboardEnabled'] != false,
      posCompactMode: json['posCompactMode'] == true,
      variantInsightsEnabled: json['variantInsightsEnabled'] == true,
      receipt: ReceiptSettingsRecord.fromJson(
        rawReceipt is Map<String, dynamic>
            ? rawReceipt
            : rawReceipt is Map
            ? Map<String, dynamic>.from(rawReceipt)
            : null,
      ),
      barcodeLabel: BarcodeLabelSettingsRecord.fromJson(
        rawBarcodeLabel is Map<String, dynamic>
            ? rawBarcodeLabel
            : rawBarcodeLabel is Map
            ? Map<String, dynamic>.from(rawBarcodeLabel)
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lowStockThreshold': lowStockThreshold,
      'usdRate': usdRate,
      'displayCurrency': displayCurrency,
      'keyboardEnabled': keyboardEnabled,
      'posCompactMode': posCompactMode,
      'variantInsightsEnabled': variantInsightsEnabled,
      'receipt': receipt.toJson(),
      'barcodeLabel': barcodeLabel.toJson(),
    };
  }

  AppSettingsRecord copyWith({
    int? lowStockThreshold,
    double? usdRate,
    String? displayCurrency,
    bool? keyboardEnabled,
    bool? posCompactMode,
    bool? variantInsightsEnabled,
    ReceiptSettingsRecord? receipt,
    BarcodeLabelSettingsRecord? barcodeLabel,
  }) {
    return AppSettingsRecord(
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      usdRate: usdRate ?? this.usdRate,
      displayCurrency: displayCurrency ?? this.displayCurrency,
      keyboardEnabled: keyboardEnabled ?? this.keyboardEnabled,
      posCompactMode: posCompactMode ?? this.posCompactMode,
      variantInsightsEnabled:
          variantInsightsEnabled ?? this.variantInsightsEnabled,
      receipt: receipt ?? this.receipt,
      barcodeLabel: barcodeLabel ?? this.barcodeLabel,
    );
  }
}
