import 'package:dio/dio.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which payment methods the active machine currently allows.
class PaymentAvailability {
  /// Subscription payment is allowed only when the active contract has
  /// `allow_subscriptions` set. Disabled until the contract has been loaded.
  final bool subscriptionAllowed;

  /// Card payment is disabled while the sensor named "POS" reads 0.
  final bool cardAvailable;

  const PaymentAvailability({
    required this.subscriptionAllowed,
    required this.cardAvailable,
  });

  static const PaymentAvailability initial = PaymentAvailability(
    subscriptionAllowed: false,
    cardAvailable: true,
  );
}

class PaymentAvailabilityNotifier extends Notifier<PaymentAvailability> {
  int _requestId = 0;

  @override
  PaymentAvailability build() => PaymentAvailability.initial;

  /// Reloads the availability for [serial]. When several refreshes overlap,
  /// only the most recent one updates the state.
  Future<void> refresh(String serial) async {
    final requestId = ++_requestId;
    final subscriptionAllowed = await _loadSubscriptionAllowed(serial);
    final cardAvailable = await _loadCardAvailable(serial);
    if (requestId != _requestId) {
      return;
    }
    state = PaymentAvailability(
      subscriptionAllowed: subscriptionAllowed,
      cardAvailable: cardAvailable,
    );
  }

  // A machine without an active contract (404) does not allow subscriptions.
  Future<bool> _loadSubscriptionAllowed(String serial) async {
    try {
      final response = await ProductService.getMachineContract(serial);
      final data = response.data;
      return data is Map && data['allow_subscriptions'] == true;
    } on DioException {
      return false;
    }
  }

  // Card payment is only blocked when the POS sensor reads exactly 0. A
  // missing sensor or reading keeps card payment available.
  Future<bool> _loadCardAvailable(String serial) async {
    try {
      final response = await ProductService.getSensorList(
        machineSerial: serial,
      );
      final data = response.data;
      if (data is! List) {
        return true;
      }
      for (final sensor in data) {
        if (sensor is Map &&
            sensor['name']?.toString().trim().toUpperCase() == 'POS') {
          final value = num.tryParse(sensor['last_value']?.toString() ?? '');
          return value != 0;
        }
      }
      return true;
    } on DioException {
      return true;
    }
  }
}

final paymentAvailabilityProvider =
    NotifierProvider<PaymentAvailabilityNotifier, PaymentAvailability>(() {
      return PaymentAvailabilityNotifier();
    });

/// Convenience: refreshes the availability for the currently active machine.
Future<void> refreshPaymentAvailability(WidgetRef ref) {
  return ref
      .read(paymentAvailabilityProvider.notifier)
      .refresh(ref.read(activeMachineProvider));
}
