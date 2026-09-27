/// A batch of machine receipts produced by one finalized order.
///
/// The backend groups `Machine_Receipt` rows that share the same `serial`;
/// the whole batch corresponds to a single order. The loading page polls for
/// the latest such batch and hands it to the order-preparation page.
class ReceiptBatch {
  /// Serial shared by every receipt of this batch.
  final int serial;
  final String creationDate;

  final int totalPrice;
  final int totalDiscount;

  final List<ReceiptBatchItem> items;

  const ReceiptBatch({
    required this.serial,
    required this.creationDate,
    required this.totalPrice,
    required this.totalDiscount,
    required this.items,
  });

  static const ReceiptBatch empty = ReceiptBatch(
    serial: 0,
    creationDate: '',
    totalPrice: 0,
    totalDiscount: 0,
    items: <ReceiptBatchItem>[],
  );

  /// Parses the `/getlatestreceiptbatch` payload, or returns null when the
  /// backend reports that no eligible batch exists yet.
  static ReceiptBatch? fromResponse(dynamic data) {
    if (data is! Map || data['found'] != true) {
      return null;
    }
    final rawItems = data['items'];
    final items = <ReceiptBatchItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          items.add(ReceiptBatchItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }

    // A batch without any product line cannot be prepared, so treat it as
    // "not ready yet" rather than navigating to a page with nothing to show.
    if (items.isEmpty) {
      return null;
    }

    return ReceiptBatch(
      serial: _toInt(data['serial']),
      creationDate: data['creation_date']?.toString() ?? '',
      totalPrice: _toInt(data['total_price']),
      totalDiscount: _toInt(data['total_discount']),
      items: items,
    );
  }

  static int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// A single product line inside a [ReceiptBatch].
class ReceiptBatchItem {
  final String productSerial;
  final String productName;
  final int quantity;
  final int finalPrice;
  final int discountAmount;
  final int companyShare;
  final int type;

  const ReceiptBatchItem({
    required this.productSerial,
    required this.productName,
    required this.quantity,
    required this.finalPrice,
    required this.discountAmount,
    required this.companyShare,
    required this.type,
  });

  factory ReceiptBatchItem.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) {
      if (value is num) {
        return value.toInt();
      }
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return ReceiptBatchItem(
      productSerial: json['product_serial']?.toString() ?? '',
      productName: json['product_name']?.toString() ?? '',
      quantity: asInt(json['quantity']),
      finalPrice: asInt(json['final_price']),
      discountAmount: asInt(json['discount_amount']),
      companyShare: asInt(json['company_share']),
      type: asInt(json['type']),
    );
  }
}
