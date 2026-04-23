import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';
import '../../categories/domain/category_record.dart';
import '../domain/product_record.dart';
import '../../suppliers/domain/supplier_record.dart';

final productsRepositoryProvider = Provider<ProductsRepository>((ref) {
  return ProductsRepository(ref.watch(dioProvider));
});

class ProductsRepository {
  ProductsRepository(this._dio);

  final Dio _dio;
  static const _centralApiBaseUrl = 'https://ataway.richman.uz/api';
  static const _centralSyncUsername = 'admin';
  static const _centralSyncPassword = '0000';
  static const _defaultStoreCode = '7909';
  static const _defaultStoreName = 'ataway';

  Future<List<ProductRecord>> fetchProducts({
    required String token,
    String categoryId = '',
    String searchQuery = '',
  }) async {
    final trimmedQuery = searchQuery.trim();
    final queryParameters = <String, dynamic>{};
    if (categoryId.isNotEmpty) {
      queryParameters['categoryId'] = categoryId;
    }
    if (trimmedQuery.isNotEmpty) {
      queryParameters['q'] = trimmedQuery;
    }
    final response = await _dio.get<Map<String, dynamic>>(
      '/products',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['products'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              ProductRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> createProduct({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    await _dio.post<void>(
      '/products',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> updateProduct({
    required String token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    await _dio.put<void>(
      '/products/$id',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> deleteProduct({
    required String token,
    required String id,
  }) async {
    await _dio.delete<void>(
      '/products/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<void> restockProduct({
    required String token,
    required String id,
    required Map<String, dynamic> payload,
  }) async {
    await _dio.post<void>(
      '/products/$id/restock',
      data: payload,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<Map<String, dynamic>> syncCentralTransfers({
    required String token,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/products/sync-central',
        data: const {
          'storeCode': _defaultStoreCode,
          'storeName': _defaultStoreName,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data ?? const <String, dynamic>{};
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      return _syncCentralTransfersClientSide(token: token);
    }
  }

  Future<List<ProductRecord>> fetchTopProducts({
    required String token,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/products/top',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['products'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              ProductRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<ProductRecord>> saveTopProducts({
    required String token,
    required List<String> productIds,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/products/top',
      data: {'productIds': productIds},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['products'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              ProductRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> _syncCentralTransfersClientSide({
    required String token,
  }) async {
    final localProducts = await fetchProducts(token: token);
    final localCategories = await _fetchCategories(token);
    final localSuppliers = await _fetchSuppliers(token);

    final central = Dio(
      BaseOptions(
        baseUrl: _centralApiBaseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    final login = await central.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'username': _centralSyncUsername,
        'password': _centralSyncPassword,
      },
    );
    final centralToken = login.data?['token']?.toString() ?? '';
    if (centralToken.isEmpty) {
      throw Exception('Markaziy server token qaytarmadi');
    }

    final transfersResponse = await central.get<Map<String, dynamic>>(
      '/transfers',
      options: Options(
        headers: {'Authorization': 'Bearer $centralToken'},
      ),
    );
    final rawTransfers =
        (transfersResponse.data?['transfers'] as List?) ?? const [];
    final storeTransfers = rawTransfers
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where(
          (item) =>
              (item['status']?.toString().trim().toLowerCase() ?? '') ==
                  'sent' &&
              ((item['storeCode']?.toString().trim() ?? '') ==
                      _defaultStoreCode ||
                  (item['storeName']?.toString().trim().toLowerCase() ?? '') ==
                      _defaultStoreName),
        )
        .toList();

    if (storeTransfers.isEmpty) {
      return const {
        'syncedTransfers': 0,
        'syncedProducts': 0,
        'skippedTransfers': 0,
        'message': 'Sinxron uchun yangi transfer topilmadi',
      };
    }

    final syncedTransferIds = await _loadSyncedTransferIds();
    final pendingTransfers = storeTransfers.where((transfer) {
      final id = transfer['_id']?.toString() ?? '';
      return id.isNotEmpty && !syncedTransferIds.contains(id);
    }).toList();

    if (pendingTransfers.isEmpty) {
      return {
        'syncedTransfers': 0,
        'syncedProducts': 0,
        'skippedTransfers': storeTransfers.length,
        'message': 'Barcha transferlar oldin sinxron qilingan',
      };
    }

    final productsByBarcode = <String, _LocalProductState>{
      for (final product in localProducts)
        if (product.barcode.trim().isNotEmpty)
          product.barcode.trim(): _LocalProductState.fromProduct(product),
    };
    final categoriesByName = <String, CategoryRecord>{
      for (final category in localCategories)
        category.name.trim().toLowerCase(): category,
    };
    final suppliersByName = <String, SupplierRecord>{
      for (final supplier in localSuppliers)
        supplier.name.trim().toLowerCase(): supplier,
    };

    final allBarcodes = <String>{
      for (final transfer in pendingTransfers)
        ...((transfer['items'] as List?) ?? const [])
            .map((item) => (item as Map)['barcode']?.toString().trim() ?? '')
            .where((barcode) => barcode.isNotEmpty),
    };

    final remoteProducts = <String, Map<String, dynamic>>{};
    for (final barcode in allBarcodes) {
      final remote = await central.get<Map<String, dynamic>>(
        '/products',
        queryParameters: {'q': barcode},
        options: Options(
          headers: {'Authorization': 'Bearer $centralToken'},
        ),
      );
      final products = (remote.data?['products'] as List?) ?? const [];
      final matched = products
          .map((item) => Map<String, dynamic>.from(item as Map))
          .cast<Map<String, dynamic>?>()
          .firstWhere(
            (item) => (item?['barcode']?.toString().trim() ?? '') == barcode,
            orElse: () => null,
          );
      if (matched != null) {
        remoteProducts[barcode] = matched;
      }
    }

    var syncedTransfers = 0;
    var syncedProducts = 0;

    for (final transfer in pendingTransfers) {
      final transferItems =
          (transfer['items'] as List?)?.cast<dynamic>() ?? const [];
      for (final rawItem in transferItems) {
        final item = Map<String, dynamic>.from(rawItem as Map);
        final barcode = item['barcode']?.toString().trim() ?? '';
        final incomingQuantity = _toDouble(item['quantity']);
        if (barcode.isEmpty || incomingQuantity <= 0) {
          continue;
        }

        final remoteProduct = remoteProducts[barcode] ?? const <String, dynamic>{};
        final category = await _ensureCategory(
          token: token,
          categoriesByName: categoriesByName,
          desiredName:
              _nestedString(remoteProduct, ['categoryId', 'name']) ??
              'Sinxron kategoriya',
        );
        final supplier = await _ensureSupplier(
          token: token,
          suppliersByName: suppliersByName,
          desiredName:
              _nestedString(remoteProduct, ['supplierId', 'name']) ??
              'Sklad transfer',
        );

        final unit = (remoteProduct['unit']?.toString().trim().toLowerCase() ??
                item['unit']?.toString().trim().toLowerCase() ??
                'dona')
            .trim();
        final purchasePrice = _roundMoney(
          _toDouble(item['purchasePrice']) > 0
              ? _toDouble(item['purchasePrice'])
              : _toDouble(remoteProduct['purchasePrice']),
        );
        final retailPrice = _roundMoney(
          _toDouble(remoteProduct['retailPrice']) > 0
              ? _toDouble(remoteProduct['retailPrice'])
              : purchasePrice,
        );
        final wholesalePrice = _roundMoney(
          _toDouble(remoteProduct['wholesalePrice']) > 0
              ? _toDouble(remoteProduct['wholesalePrice'])
              : retailPrice,
        );
        final transferredVariantStocks = _normalizeVariantStocks(
          item['variants'] ?? item['variantStocks'],
        );
        final remoteVariantStocks = _normalizeVariantStocks(
          remoteProduct['variantStocks'],
        );
        final effectiveVariantStocks = transferredVariantStocks.isNotEmpty
            ? transferredVariantStocks
            : remoteVariantStocks;
        final sizeOptions = _normalizeStringList([
          ..._toStringList(remoteProduct['sizeOptions']),
          ...effectiveVariantStocks.map((variant) => variant.size),
        ]);
        final colorOptions = _normalizeStringList([
          ..._toStringList(remoteProduct['colorOptions']),
          ...effectiveVariantStocks.map((variant) => variant.color),
        ]);

        final existing = productsByBarcode[barcode];
        if (existing == null) {
          final payload = <String, dynamic>{
            'name': (remoteProduct['name']?.toString().trim().isNotEmpty ?? false)
                ? remoteProduct['name']?.toString().trim()
                : item['name']?.toString().trim() ?? 'Transfer mahsulot',
            'model': (remoteProduct['model']?.toString().trim().isNotEmpty ?? false)
                ? remoteProduct['model']?.toString().trim()
                : item['model']?.toString().trim() ?? '-',
            'barcode': barcode,
            'gender': remoteProduct['gender']?.toString() ?? '',
            'categoryId': category.id,
            'supplierId': supplier.id,
            'purchasePrice': purchasePrice,
            'priceCurrency': 'uzs',
            'retailPrice': retailPrice,
            'wholesalePrice': wholesalePrice,
            'paymentType': 'naqd',
            'paidAmount': _roundMoney(purchasePrice * incomingQuantity),
            'quantity': incomingQuantity,
            'unit': unit.isEmpty ? 'dona' : unit,
            'sizeOptions': sizeOptions,
            'colorOptions': colorOptions,
            'variantStocks': effectiveVariantStocks
                .map(
                  (variant) => {
                    'size': variant.size,
                    'color': variant.color,
                    'quantity': variant.quantity,
                  },
                )
                .toList(),
            'allowPieceSale': remoteProduct['allowPieceSale'] == true,
            'pieceUnit': remoteProduct['pieceUnit']?.toString() ?? 'kg',
            'pieceQtyPerBase': _toDouble(remoteProduct['pieceQtyPerBase']),
            'piecePrice': _toDouble(remoteProduct['piecePrice']),
          };

          final created = await _dio.post<Map<String, dynamic>>(
            '/products',
            data: payload,
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          final createdId = created.data?['product']?['_id']?.toString() ?? '';
          productsByBarcode[barcode] = _LocalProductState(
            id: createdId,
            name: payload['name']?.toString() ?? '',
            model: payload['model']?.toString() ?? '',
            barcode: barcode,
            gender: payload['gender']?.toString() ?? '',
            categoryId: category.id,
            supplierId: supplier.id,
            purchasePrice: purchasePrice,
            priceCurrency: 'uzs',
            retailPrice: retailPrice,
            wholesalePrice: wholesalePrice,
            paymentType: 'naqd',
            paidAmount: _roundMoney(purchasePrice * incomingQuantity),
            quantity: incomingQuantity,
            unit: payload['unit']?.toString() ?? 'dona',
            sizeOptions: sizeOptions,
            colorOptions: colorOptions,
            variantStocks: effectiveVariantStocks,
            allowPieceSale: payload['allowPieceSale'] == true,
            pieceUnit: payload['pieceUnit']?.toString() ?? 'kg',
            pieceQtyPerBase: _toDouble(payload['pieceQtyPerBase']),
            piecePrice: _toDouble(payload['piecePrice']),
          );
        } else {
          await _dio.post<void>(
            '/products/${existing.id}/restock',
            data: {
              'supplierId': supplier.id,
              'quantity': incomingQuantity,
              'purchasePrice': purchasePrice,
              'priceCurrency': 'uzs',
              'pricingMode': 'replace_all',
              'retailPrice': retailPrice,
              'wholesalePrice': wholesalePrice,
              'piecePrice': _toDouble(remoteProduct['piecePrice']),
              'paymentType': 'naqd',
              'paidAmount': _roundMoney(purchasePrice * incomingQuantity),
            },
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );

          final mergedVariantStocks = _mergeVariantStocks(
            existing.variantStocks,
            effectiveVariantStocks,
          );
          final nextQuantity = _roundMoney(existing.quantity + incomingQuantity);
          final nextSizeOptions = _normalizeStringList([
            ...existing.sizeOptions,
            ...sizeOptions,
            ...mergedVariantStocks.map((variant) => variant.size),
          ]);
          final nextColorOptions = _normalizeStringList([
            ...existing.colorOptions,
            ...colorOptions,
            ...mergedVariantStocks.map((variant) => variant.color),
          ]);

          final updatePayload = <String, dynamic>{
            'name': (remoteProduct['name']?.toString().trim().isNotEmpty ?? false)
                ? remoteProduct['name']?.toString().trim()
                : existing.name,
            'model': (remoteProduct['model']?.toString().trim().isNotEmpty ?? false)
                ? remoteProduct['model']?.toString().trim()
                : existing.model,
            'barcode': barcode,
            'gender': remoteProduct['gender']?.toString() ?? existing.gender,
            'categoryId': category.id,
            'supplierId': supplier.id,
            'purchasePrice': purchasePrice,
            'priceCurrency': 'uzs',
            'retailPrice': retailPrice,
            'wholesalePrice': wholesalePrice,
            'paymentType': 'naqd',
            'paidAmount': _roundMoney(purchasePrice * nextQuantity),
            'quantity': nextQuantity,
            'unit': unit.isEmpty ? existing.unit : unit,
            'sizeOptions': nextSizeOptions,
            'colorOptions': nextColorOptions,
            'variantStocks': mergedVariantStocks
                .map(
                  (variant) => {
                    'size': variant.size,
                    'color': variant.color,
                    'quantity': variant.quantity,
                  },
                )
                .toList(),
            'allowPieceSale': remoteProduct['allowPieceSale'] == true ||
                existing.allowPieceSale,
            'pieceUnit': remoteProduct['pieceUnit']?.toString() ??
                existing.pieceUnit,
            'pieceQtyPerBase': _toDouble(remoteProduct['pieceQtyPerBase']) > 0
                ? _toDouble(remoteProduct['pieceQtyPerBase'])
                : existing.pieceQtyPerBase,
            'piecePrice': _toDouble(remoteProduct['piecePrice']) > 0
                ? _toDouble(remoteProduct['piecePrice'])
                : existing.piecePrice,
          };

          await _dio.put<void>(
            '/products/${existing.id}',
            data: updatePayload,
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );

          productsByBarcode[barcode] = existing.copyWith(
            name: updatePayload['name']?.toString() ?? existing.name,
            model: updatePayload['model']?.toString() ?? existing.model,
            gender: updatePayload['gender']?.toString() ?? existing.gender,
            categoryId: category.id,
            supplierId: supplier.id,
            purchasePrice: purchasePrice,
            retailPrice: retailPrice,
            wholesalePrice: wholesalePrice,
            paidAmount: _roundMoney(purchasePrice * nextQuantity),
            quantity: nextQuantity,
            unit: updatePayload['unit']?.toString() ?? existing.unit,
            sizeOptions: nextSizeOptions,
            colorOptions: nextColorOptions,
            variantStocks: mergedVariantStocks,
            allowPieceSale: updatePayload['allowPieceSale'] == true,
            pieceUnit: updatePayload['pieceUnit']?.toString() ?? existing.pieceUnit,
            pieceQtyPerBase: _toDouble(updatePayload['pieceQtyPerBase']),
            piecePrice: _toDouble(updatePayload['piecePrice']),
          );
        }
        syncedProducts += 1;
      }

      final transferId = transfer['_id']?.toString() ?? '';
      if (transferId.isNotEmpty) {
        syncedTransferIds.add(transferId);
      }
      syncedTransfers += 1;
    }

    await _saveSyncedTransferIds(syncedTransferIds);

    return {
      'syncedTransfers': syncedTransfers,
      'syncedProducts': syncedProducts,
      'skippedTransfers': storeTransfers.length - pendingTransfers.length,
      'message': '$syncedTransfers ta transfer sinxron qilindi',
    };
  }

  Future<List<CategoryRecord>> _fetchCategories(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/categories',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['categories'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              CategoryRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<SupplierRecord>> _fetchSuppliers(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/suppliers',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final raw = (response.data?['suppliers'] as List?) ?? const [];
    return raw
        .map(
          (item) =>
              SupplierRecord.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<CategoryRecord> _ensureCategory({
    required String token,
    required Map<String, CategoryRecord> categoriesByName,
    required String desiredName,
  }) async {
    final normalized = desiredName.trim().isEmpty
        ? 'sinxron kategoriya'
        : desiredName.trim().toLowerCase();
    final existing = categoriesByName[normalized];
    if (existing != null) return existing;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/categories',
        data: {'name': desiredName.trim().isEmpty ? 'Sinxron kategoriya' : desiredName.trim()},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final created = CategoryRecord.fromJson(
        Map<String, dynamic>.from((response.data?['category'] as Map?) ?? {}),
      );
      categoriesByName[created.name.trim().toLowerCase()] = created;
      return created;
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      final refreshed = await _fetchCategories(token);
      for (final category in refreshed) {
        categoriesByName[category.name.trim().toLowerCase()] = category;
      }
      final matched = categoriesByName[normalized];
      if (matched != null) return matched;
      throw Exception('Kategoriya yaratilmadi: $desiredName');
    }
  }

  Future<SupplierRecord> _ensureSupplier({
    required String token,
    required Map<String, SupplierRecord> suppliersByName,
    required String desiredName,
  }) async {
    final normalized = desiredName.trim().isEmpty
        ? 'sklad transfer'
        : desiredName.trim().toLowerCase();
    final existing = suppliersByName[normalized];
    if (existing != null) return existing;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/suppliers',
        data: {
          'name': desiredName.trim().isEmpty ? 'Sklad transfer' : desiredName.trim(),
          'address': 'Sklad transfer',
          'phone': '',
          'openingBalanceAmount': 0,
          'openingBalanceCurrency': 'uzs',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final created = SupplierRecord.fromJson(
        Map<String, dynamic>.from((response.data?['supplier'] as Map?) ?? {}),
      );
      suppliersByName[created.name.trim().toLowerCase()] = created;
      return created;
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      final refreshed = await _fetchSuppliers(token);
      for (final supplier in refreshed) {
        suppliersByName[supplier.name.trim().toLowerCase()] = supplier;
      }
      final matched = suppliersByName[normalized];
      if (matched != null) return matched;
      throw Exception('Yetkazib beruvchi yaratilmadi: $desiredName');
    }
  }

  String _syncTransferPrefsKey() =>
      'synced_transfer_ids::${_dio.options.baseUrl.trim().toLowerCase()}';

  Future<Set<String>> _loadSyncedTransferIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_syncTransferPrefsKey()) ?? const <String>[])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  Future<void> _saveSyncedTransferIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_syncTransferPrefsKey(), ids.toList()..sort());
  }
}

class _LocalVariantStock {
  const _LocalVariantStock({
    required this.size,
    required this.color,
    required this.quantity,
  });

  final String size;
  final String color;
  final double quantity;
}

class _LocalProductState {
  const _LocalProductState({
    required this.id,
    required this.name,
    required this.model,
    required this.barcode,
    required this.gender,
    required this.categoryId,
    required this.supplierId,
    required this.purchasePrice,
    required this.priceCurrency,
    required this.retailPrice,
    required this.wholesalePrice,
    required this.paymentType,
    required this.paidAmount,
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
  final String gender;
  final String categoryId;
  final String supplierId;
  final double purchasePrice;
  final String priceCurrency;
  final double retailPrice;
  final double wholesalePrice;
  final String paymentType;
  final double paidAmount;
  final double quantity;
  final String unit;
  final List<String> sizeOptions;
  final List<String> colorOptions;
  final List<_LocalVariantStock> variantStocks;
  final bool allowPieceSale;
  final String pieceUnit;
  final double pieceQtyPerBase;
  final double piecePrice;

  factory _LocalProductState.fromProduct(ProductRecord product) {
    return _LocalProductState(
      id: product.id,
      name: product.name,
      model: product.model,
      barcode: product.barcode,
      gender: product.gender,
      categoryId: product.category.id,
      supplierId: product.supplier.id,
      purchasePrice: product.purchasePrice,
      priceCurrency: product.priceCurrency,
      retailPrice: product.retailPrice,
      wholesalePrice: product.wholesalePrice,
      paymentType: product.paymentType,
      paidAmount: product.paidAmount,
      quantity: product.quantity,
      unit: product.unit,
      sizeOptions: product.sizeOptions,
      colorOptions: product.colorOptions,
      variantStocks: product.variantStocks
          .map(
            (variant) => _LocalVariantStock(
              size: variant.size,
              color: variant.color,
              quantity: variant.quantity,
            ),
          )
          .toList(),
      allowPieceSale: product.allowPieceSale,
      pieceUnit: product.pieceUnit,
      pieceQtyPerBase: product.pieceQtyPerBase,
      piecePrice: product.piecePrice,
    );
  }

  _LocalProductState copyWith({
    String? name,
    String? model,
    String? gender,
    String? categoryId,
    String? supplierId,
    double? purchasePrice,
    double? retailPrice,
    double? wholesalePrice,
    double? paidAmount,
    double? quantity,
    String? unit,
    List<String>? sizeOptions,
    List<String>? colorOptions,
    List<_LocalVariantStock>? variantStocks,
    bool? allowPieceSale,
    String? pieceUnit,
    double? pieceQtyPerBase,
    double? piecePrice,
  }) {
    return _LocalProductState(
      id: id,
      name: name ?? this.name,
      model: model ?? this.model,
      barcode: barcode,
      gender: gender ?? this.gender,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      priceCurrency: priceCurrency,
      retailPrice: retailPrice ?? this.retailPrice,
      wholesalePrice: wholesalePrice ?? this.wholesalePrice,
      paymentType: paymentType,
      paidAmount: paidAmount ?? this.paidAmount,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      sizeOptions: sizeOptions ?? this.sizeOptions,
      colorOptions: colorOptions ?? this.colorOptions,
      variantStocks: variantStocks ?? this.variantStocks,
      allowPieceSale: allowPieceSale ?? this.allowPieceSale,
      pieceUnit: pieceUnit ?? this.pieceUnit,
      pieceQtyPerBase: pieceQtyPerBase ?? this.pieceQtyPerBase,
      piecePrice: piecePrice ?? this.piecePrice,
    );
  }
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _roundMoney(double value) {
  return (value * 100).roundToDouble() / 100;
}

List<String> _toStringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
}

List<String> _normalizeStringList(Iterable<String> values) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    final key = value.toLowerCase();
    if (value.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    result.add(value);
  }
  return result;
}

String? _nestedString(Map<String, dynamic> source, List<String> path) {
  dynamic current = source;
  for (final key in path) {
    if (current is Map && current.containsKey(key)) {
      current = current[key];
    } else {
      return null;
    }
  }
  final value = current?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

List<_LocalVariantStock> _normalizeVariantStocks(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{})
      .map(
        (item) => _LocalVariantStock(
          size: item['size']?.toString().trim() ?? '',
          color: item['color']?.toString().trim() ?? '',
          quantity: _toDouble(item['quantity']),
        ),
      )
      .where(
        (item) =>
            item.size.isNotEmpty && item.color.isNotEmpty && item.quantity > 0,
      )
      .toList();
}

List<_LocalVariantStock> _mergeVariantStocks(
  List<_LocalVariantStock> current,
  List<_LocalVariantStock> incoming,
) {
  final bucket = <String, _LocalVariantStock>{};

  for (final item in current) {
    bucket['${item.size}::${item.color}'] = item;
  }
  for (final item in incoming) {
    final key = '${item.size}::${item.color}';
    final existing = bucket[key];
    if (existing == null) {
      bucket[key] = item;
    } else {
      bucket[key] = _LocalVariantStock(
        size: existing.size,
        color: existing.color,
        quantity: _roundMoney(existing.quantity + item.quantity),
      );
    }
  }

  return bucket.values.where((item) => item.quantity > 0).toList();
}
