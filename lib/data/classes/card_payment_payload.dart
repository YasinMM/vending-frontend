import 'dart:convert';

import 'package:flutter_production_test/data/classes/utc_time.dart';

/// Order data handed over to the card swipe page running in its own browser
/// tab.
///
/// That tab is a separate Flutter app instance, so the Riverpod state of the
/// main tab (selected products, discounts, active user) is not available
/// there. The order is therefore encoded as base64 JSON in the URL fragment,
/// the same way the online payment page does it.
class CardPaymentPayload {
  /// A plain card purchase of the ordered products.
  static const String kindPurchase = 'purchase';

  /// A wallet top-up that is followed by the purchase it is paying for.
  static const String kindWalletTopUp = 'wallet_topup';

  final String kind;

  final String creationDate;
  final int user;
  final String machineSerial;
  final List<String> discountCodes;
  final String bankSerial;

  // Purchase fields.
  final int? amount;
  final List<String> productSerials;
  final List<int> quantities;

  // Wallet top-up fields.
  final int? depositAmount;
  final int? purchaseAmount;

  const CardPaymentPayload({
    required this.kind,
    required this.creationDate,
    required this.user,
    required this.machineSerial,
    required this.discountCodes,
    required this.bankSerial,
    this.amount,
    this.productSerials = const <String>[],
    this.quantities = const <int>[],
    this.depositAmount,
    this.purchaseAmount,
  });

  bool get isWalletTopUp => kind == kindWalletTopUp;

  /// Builds the payload for a plain purchase.
  factory CardPaymentPayload.purchase({
    required int user,
    required String machineSerial,
    required List<String> discountCodes,
    required int amount,
    required List<String> productSerials,
    required List<int> quantities,
  }) {
    return CardPaymentPayload(
      kind: kindPurchase,
      creationDate: utcNowIso(),
      user: user,
      machineSerial: machineSerial,
      discountCodes: discountCodes,
      bankSerial: '234556',
      amount: amount,
      productSerials: productSerials,
      quantities: quantities,
    );
  }

  /// Builds the payload for a wallet top-up plus its purchase.
  factory CardPaymentPayload.walletTopUp({
    required int user,
    required String machineSerial,
    required List<String> discountCodes,
    required int depositAmount,
    required int purchaseAmount,
    required List<String> productSerials,
    required List<int> quantities,
  }) {
    return CardPaymentPayload(
      kind: kindWalletTopUp,
      creationDate: utcNowIso(),
      user: user,
      machineSerial: machineSerial,
      discountCodes: discountCodes,
      bankSerial: '123456',
      depositAmount: depositAmount,
      purchaseAmount: purchaseAmount,
      productSerials: productSerials,
      quantities: quantities,
    );
  }

  /// Encodes the payload into the query part of the card swipe route.
  String encode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'creation_date': creationDate,
      'user': user,
      'machine_serial': machineSerial,
      'discount_codes': discountCodes,
      'bank_serial': bankSerial,
      'amount': amount,
      'product_serials': productSerials,
      'quantities': quantities,
      'deposit_amount': depositAmount,
      'purchase_amount': purchaseAmount,
    };
  }

  /// Reads a payload back from the URL of the card swipe page.
  /// Returns null when the page was opened without order data.
  static CardPaymentPayload? fromUrl() {
    var query = Uri.base.queryParameters['data'];
    if (query == null || query.isEmpty) {
      // The app uses hash routing, so the data may live in the fragment.
      final fragment = Uri.base.fragment;
      final index = fragment.indexOf('data=');
      if (index < 0) {
        return null;
      }
      query = fragment.substring(index + 'data='.length);
    }
    if (query.isEmpty) {
      return null;
    }
    try {
      final decoded = utf8.decode(base64Url.decode(query));
      return CardPaymentPayload.fromJson(
        Map<String, dynamic>.from(jsonDecode(decoded) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  factory CardPaymentPayload.fromJson(Map<String, dynamic> json) {
    return CardPaymentPayload(
      kind: json['kind']?.toString() ?? kindPurchase,
      creationDate: json['creation_date']?.toString() ?? '',
      user: _toInt(json['user'], fallback: -1),
      machineSerial: json['machine_serial']?.toString() ?? '',
      discountCodes: _toStringList(json['discount_codes']),
      bankSerial: json['bank_serial']?.toString() ?? '234556',
      amount: _toNullableInt(json['amount']),
      productSerials: _toStringList(json['product_serials']),
      quantities: _toIntList(json['quantities']),
      depositAmount: _toNullableInt(json['deposit_amount']),
      purchaseAmount: _toNullableInt(json['purchase_amount']),
    );
  }

  static int _toInt(Object? value, {int fallback = 0}) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _toNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static List<String> _toStringList(Object? value) {
    if (value is! List) {
      return <String>[];
    }
    return value.map((e) => e.toString()).toList();
  }

  static List<int> _toIntList(Object? value) {
    if (value is! List) {
      return <int>[];
    }
    return value.map((e) => _toInt(e)).toList();
  }
}
