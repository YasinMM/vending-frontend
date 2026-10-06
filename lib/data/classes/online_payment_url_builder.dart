import 'dart:convert';

import 'package:flutter_production_test/data/classes/utc_time.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds the online-payment URL for the current order.
///
/// The order is encoded as base64 JSON in the URL fragment so the page works
/// in any browser (and in a separate tab, where the Riverpod state of this
/// app instance is not available).
class OnlinePaymentUrlBuilder {
  OnlinePaymentUrlBuilder._();

  /// Payload of the current order, matching what the online payment page
  /// expects when it creates the transaction.
  static Map<String, dynamic> buildPayload(
    WidgetRef ref, {
    required int qrSerial,
  }) {
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedDiscountCodes = ref
        .read(activeDiscountsProvider)
        .where((d) => d.selected)
        .map((d) => d.code)
        .toList();

    return {
      "creation_date": utcNowIso(),
      "discount_codes": selectedDiscountCodes,
      "user": ref.read(activeUserProvider),
      "bank_serial": "234556",
      "machine_serial": ref.read(activeMachineProvider),
      "product_serials": selectedProducts.map((p) => p.serial).toList(),
      "quantities": selectedProducts.map((p) => p.quantity).toList(),
      "machine_qr_code_serial": qrSerial,
    };
  }

  /// Absolute URL of the online payment page, carrying [ref]'s current order.
  static String build(WidgetRef ref, {required int qrSerial}) {
    final payload = jsonEncode(buildPayload(ref, qrSerial: qrSerial));
    final encoded = base64Url.encode(utf8.encode(payload));
    final origin = Uri.base.origin;
    final path = Uri.base.path.replaceFirst(RegExp(r'index\.html$'), '');
    return '$origin$path#/online_payment?data=$encoded';
  }
}
