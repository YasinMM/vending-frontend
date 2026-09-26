import 'dart:async';

import 'package:flutter_production_test/pages/screensaver_page.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_production_test/widgets/error_simulation_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Global inactivity timer. A few minutes after the last interaction (any
/// button click, tap, etc.) the app resets to its default state: selected
/// products, discounts and active user are cleared, and the app navigates to
/// the screensaver instead of straight back into the order flow.
///
/// Some pages opt out of the screensaver (see [exemptRoutes]): the debug page
/// and the online payment page keep running when the timer fires, because the
/// user is expected to be working there.
class InactivityService {
  InactivityService._();

  static final InactivityService instance = InactivityService._();

  static const Duration timeout = Duration(minutes: 3);

  /// Routes that must not be interrupted by the screensaver. The timer still
  /// resets state on them, but the user stays where they are.
  static const Set<String> exemptRoutes = {
    ErrorSimulationButton.routePath,
    '/online_payment',
  };

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

    // Exempt pages stay where they are; everything else shows the screensaver
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (exemptRoutes.contains(location)) {
      // Keep the timer armed so leaving the page still has a countdown.
      reset();
      return;
    }

    router.go(ScreensaverPage.routePath);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
