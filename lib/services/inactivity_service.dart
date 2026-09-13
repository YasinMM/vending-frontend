import 'dart:async';

import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Global inactivity timer. One minute after the last interaction
/// (any button click, tap, etc.) the app resets to its default state:
/// selected products, discounts and active user are cleared and the
/// app navigates back to the products page.
class InactivityService {
  InactivityService._();

  static final InactivityService instance = InactivityService._();

  static const Duration timeout = Duration(minutes: 1);

  Timer? _timer;
  WidgetRef? _ref;
  GoRouter? _router;

  /// Must be called once at app startup with the root ref and router.
  void configure(WidgetRef ref, GoRouter router) {
    _ref = ref;
    _router = router;
  }

  /// Resets the countdown. Call on every user interaction.
  void reset() {
    _timer?.cancel();
    if (_ref == null) {
      return;
    }
    _timer = Timer(timeout, _onTimeout);
  }

  void _onTimeout() {
    final ref = _ref;
    final router = _router;
    if (ref == null || router == null) {
      return;
    }

    // Reset everything to its default state
    ref.read(activeUserProvider.notifier).setUser(-1);
    ref.read(selectedProductsProvider.notifier).setProducts([]);
    ref.read(activeDiscountsProvider.notifier).setDiscounts([]);

    // Navigate back to the products page
    router.go("/");
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
