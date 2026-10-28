import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_production_test/pages/screensaver_page.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/error_simulation_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Global inactivity timer. After the active machine's `standby_time` (in
/// minutes) without any interaction (any button click, tap, etc.) the app
/// resets to its default state: selected
/// products, discounts and active user are cleared, and the app navigates to
/// the screensaver instead of straight back into the order flow.
///
/// Some pages opt out of the screensaver (see [exemptRoutes]): the debug page
/// and the online payment page keep running when the timer fires, because the
/// user is expected to be working there.
class InactivityService {
  InactivityService._();

  static final InactivityService instance = InactivityService._();

  /// Used until the active machine's `standby_time` has been loaded, or when
  /// the machine has no usable value.
  static const Duration defaultTimeout = Duration(minutes: 3);

  /// Routes that must not be interrupted by the screensaver. The timer still
  /// resets state on them, but the user stays where they are.
  static const Set<String> exemptRoutes = {
    ErrorSimulationButton.routePath,
    '/online_payment',
    '/card_swipe',
  };

  Timer? _timer;
  WidgetRef? _ref;
  GoRouter? _router;
  Duration _timeout = defaultTimeout;
  int _timeoutRequestId = 0;
  int _holdCount = 0;

  /// Must be called once at app startup with the root ref and router.
  void configure(WidgetRef ref, GoRouter router) {
    _ref = ref;
    _router = router;
    setMachine(ref.read(activeMachineProvider));
  }

  /// Call whenever the active machine changes. Loads that machine's
  /// `standby_time` (in minutes) and restarts the countdown with it.
  void setMachine(String serial) {
    final requestId = ++_timeoutRequestId;
    _loadTimeout(serial, requestId);
  }

  Future<void> _loadTimeout(String serial, int requestId) async {
    var timeout = defaultTimeout;
    try {
      final response = await ProductService.getMachineList();
      final minutes = _standbyMinutesFor(response.data, serial);
      if (minutes != null) {
        timeout = Duration(minutes: minutes);
      }
    } on DioException {
      // Keep the default timeout; the next machine change will retry.
    }
    // Ignore the result if another machine was selected in the meantime.
    if (requestId != _timeoutRequestId) {
      return;
    }
    _timeout = timeout;
    reset();
  }

  /// Returns the `standby_time` of the machine with [serial] from the machine
  /// list, or null if the machine is missing or the value is not at least 1.
  static int? _standbyMinutesFor(dynamic data, String serial) {
    if (data is! List) {
      return null;
    }
    for (final machine in data) {
      if (machine is Map && machine['serial']?.toString() == serial) {
        final minutes = machine['standby_time'];
        return minutes is num && minutes >= 1 ? minutes.toInt() : null;
      }
    }
    return null;
  }

  /// Resets the countdown. Call on every user interaction.
  void reset() {
    _timer?.cancel();
    if (_ref == null || _holdCount > 0) {
      return;
    }
    _timer = Timer(_timeout, _onTimeout);
  }

  /// Temporarily prevents inactivity navigation while a page's own
  /// transaction/countdown timer is running. Supports nested page holds.
  void acquireHold() {
    _holdCount++;
    if (_holdCount == 1) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Releases one hold. When the final hold ends, start a fresh inactivity
  /// countdown so the hold duration does not count as user inactivity.
  void releaseHold() {
    if (_holdCount == 0) {
      return;
    }
    _holdCount--;
    if (_holdCount == 0) {
      reset();
    }
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
    _holdCount = 0;
  }
}
