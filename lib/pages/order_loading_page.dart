import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/data/classes/card_payment_payload.dart';
import 'package:flutter_production_test/data/classes/receipt_batch.dart';
import 'package:flutter_production_test/pages/card_swipe_page.dart';
import 'package:flutter_production_test/pages/order_preparation_page.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/browser_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// What the waiting page is waiting for.
enum OrderLoadingMode {
  /// Card reader / NFC ("پرداخت با کارت" / "پرداخت با شاتکارت"): the card swipe
  /// page has been opened in a new tab, and the page waits for the purchase
  /// records to appear.
  awaitPurchase,

  /// Wallet top-up ("افزایش اعتبار"): the card swipe page has been opened in a
  /// new tab, and the page waits for the deposit to appear.
  awaitWalletTopUp,

  /// Phone payment: the QR code is shown while waiting for the user to pay
  /// on their phone.
  showQrCode,
}

/// Waiting screen shown after an order has been paid for.
///
/// It polls the backend every [_pollInterval] for the newest batch of machine
/// receipts created after this page was entered. As soon as a batch is found
/// it stops querying and hands the order over to the preparation page.
///
/// A [_timeout] countdown runs in parallel; when it elapses the user is
/// returned to the first step of the order flow.
class OrderLoadingPage extends ConsumerStatefulWidget {
  static const String routePath = '/order_loading';

  /// Overall time the user may stay on this page.
  static const Duration timeout = Duration(minutes: 3);

  /// How often the receipts are polled.
  static const Duration pollInterval = Duration(seconds: 5);

  final OrderLoadingMode mode;

  /// Payment URL rendered as a QR code in [OrderLoadingMode.showQrCode].
  final String? paymentUrl;

  /// Backend QR record used to link the phone purchase to its receipt.
  final int? qrSerial;

  /// Order to hand over to the card swipe page opened in a new tab. Set for
  /// the card reader and wallet top-up modes.
  final CardPaymentPayload? cardPayload;

  const OrderLoadingPage({
    super.key,
    this.mode = OrderLoadingMode.awaitPurchase,
    this.paymentUrl,
    this.qrSerial,
    this.cardPayload,
  });

  @override
  ConsumerState<OrderLoadingPage> createState() => _OrderLoadingPageState();
}

class _OrderLoadingPageState extends ConsumerState<OrderLoadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  final persianFormatter = NumberFormat.decimalPattern('fa');

  Timer? _pollTimer;
  Timer? _countdownTimer;

  /// Lower bound for the receipt search. Backdated by a small safety margin so
  /// a purchase recorded a moment after this page opened is never missed
  /// because of clock skew between the device and the server.
  late final DateTime _searchedSince;

  int _remainingSeconds = OrderLoadingPage.timeout.inSeconds;

  /// True while a poll request is in flight, so overlapping ticks do not
  /// stack up. Must start as false: [initState] fires the first poll, and a
  /// "true" initial value would make every call bail out before the request.
  bool _isChecking = false;

  /// Consecutive failed polls, surfaced on the page so a broken query is
  /// visible instead of silently swallowed.
  int _consecutiveErrors = 0;

  /// Why the last poll returned nothing (from the backend `reason` field).
  String? _lastReason;
  bool _isCanceling = false;

  @override
  void initState() {
    super.initState();

    // Receipts created just before this page opened still belong to this
    // order (the card swipe tab may have confirmed very quickly), so the
    // search starts a little earlier rather than at this exact instant.
    _searchedSince =
        DateTime.now().toUtc().subtract(const Duration(seconds: 15));

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _remainingSeconds = OrderLoadingPage.timeout.inSeconds;
    _startCountdown();
    _startPolling();
  }

  @override
  void dispose() {
    _stopTimers();
    if (widget.mode == OrderLoadingMode.showQrCode && widget.qrSerial != null) {
      // Idempotent server-side: only pending codes are canceled. This covers
      // browser-back navigation in addition to the visible cancel controls.
      unawaited(_cancelQrCodeOnDispose(widget.qrSerial!));
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cancelQrCodeOnDispose(int serial) async {
    try {
      await ProductService.cancelMachineQRCode(serial);
    } catch (_) {
      // The page is already leaving; server-side timeout/payment checks remain
      // the fallback if this best-effort cancellation cannot reach the API.
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      final next = _remainingSeconds - 1;
      if (next <= 0) {
        _stopTimers();
        _onTimeout();
        return;
      }
      setState(() {
        _remainingSeconds = next;
      });
    });
  }

  void _startPolling() {
    _openCardSwipeTab();
    _checkForBatch();
    _pollTimer = Timer.periodic(OrderLoadingPage.pollInterval, (_) {
      _checkForBatch();
    });
  }

  // Opens the card swipe page in a new browser tab, carrying the order in the
  // URL. The user pays there; this page keeps polling for the records.
  void _openCardSwipeTab() {
    final payload = widget.cardPayload;
    if (payload == null) {
      return;
    }
    final origin = Uri.base.origin;
    final path = Uri.base.path.replaceFirst(RegExp(r'index\.html$'), '');
    final url =
        '$origin$path#${CardSwipePage.routePath}?data=${payload.encode()}';
    // Deferring to a post-frame callback avoids the "RenderBox was not laid
    // out" crash that a focus change during the tap event can cause.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      openInNewBrowserTabUrl(url);
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // Looks for a receipt batch created at or after [_searchedSince].
  Future<void> _checkForBatch() async {
    if (!mounted || _isChecking) {
      return;
    }
    _isChecking = true;
    try {
      final response = await ProductService.getLatestReceiptBatch(
        ref.read(activeMachineProvider),
        sinceIso: _searchedSince.toIso8601String(),
      );
      final batch = ReceiptBatch.fromResponse(response.data);
      if (!mounted) {
        return;
      }
      if (batch != null) {
        // Found the finalized order: stop querying and prepare it.
        _stopTimers();
        _goToPreparation(batch);
        return;
      }
      final qrIsPending = await _checkQrStatus();
      if (!mounted) {
        return;
      }
      if (qrIsPending == false) {
        _stopTimers();
        setState(() {
          _lastReason = 'qr_code_expired';
        });
        return;
      }
      // No batch yet. Report the backend's reason so an empty result is
      // distinguishable from a broken filter.
      final reason = response.data is Map
          ? (response.data as Map)['reason']
          : null;
      if (mounted) {
        setState(() {
          _consecutiveErrors = 0;
          _lastReason = reason?.toString();
        });
      }
    } on DioException catch (e) {
      // Network hiccup: the next poll retries. Counted so a persistently
      // broken request is visible on screen.
      if (mounted) {
        setState(() {
          _consecutiveErrors++;
          _lastReason = e.response?.statusCode != null
              ? 'HTTP ${e.response!.statusCode}'
              : 'network';
        });
      }
    } finally {
      _isChecking = false;
    }
  }

  void _goToPreparation(ReceiptBatch batch) {
    // `push` rather than `go`: a `go` to the same location is a no-op, so a
    // second order would keep the first order's already-built page (and its
    // stale batch). Pushing always builds a new page with the new order.
    context.push(
      OrderPreparationPage.routePath,
      extra: batch,
    );
  }

  void _onTimeout() {
    if (!mounted) {
      return;
    }
    // The order was never confirmed by the machine: send the user back to the
    // start of the flow, where the same providers drive the reset.
    _cancelQrRecordAndLeave();
  }

  // Cancels the transaction: stops the timers and drops the order, so the
  // user starts over. Same meaning as the red button on the card swipe and
  // phone payment pages.
  void _cancelTransaction() {
    _stopTimers();
    _cancelQrRecordAndLeave();
  }

  Future<void> _cancelQrRecordAndLeave() async {
    if (_isCanceling) {
      return;
    }
    _isCanceling = true;
    final qrSerial = widget.qrSerial;
    if (widget.mode == OrderLoadingMode.showQrCode && qrSerial != null) {
      try {
        await ProductService.cancelMachineQRCode(qrSerial);
      } on DioException {
        // Server-side expiry/payment validation remains authoritative.
      }
    }
    if (!mounted) {
      return;
    }
    ref.read(selectedProductsProvider.notifier).setProducts([]);
    ref.read(activeUserProvider.notifier).setUser(-1);
    context.go("/");
  }

  Future<bool?> _checkQrStatus() async {
    final qrSerial = widget.qrSerial;
    if (widget.mode != OrderLoadingMode.showQrCode || qrSerial == null) {
      return true;
    }
    try {
      final response = await ProductService.getMachineQRCode(qrSerial);
      final state = response.data is Map
          ? int.tryParse(response.data['state'].toString())
          : null;
      if (state == 1) {
        return true;
      }
      if (state == 3 || state == null) {
        return false;
      }
      // Finished means payment succeeded; keep waiting for its receipt batch.
      return null;
    } on DioException {
      // A transient status failure must not falsely expire a valid QR.
      return null;
    }
  }

  Future<void> _expireQrAndLeave() async {
    _stopTimers();
    await _cancelQrRecordAndLeave();
  }

  void _onOkPressUp() {
    _cancelTransaction();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('در حال ثبت سفارش'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.mode == OrderLoadingMode.showQrCode)
                _buildQrSection()
              else
                _buildWaitingSection(),
              const SizedBox(height: 32),
              _buildCountdown(),
              const SizedBox(height: 12),
              // Poll status: makes a failing request visible instead of
              // looking like "just still waiting".
              if (_consecutiveErrors > 0)
                Text(
                  'خطا در دریافت اطلاعات رسید ($_consecutiveErrors تلاش ناموفق)',
                  textDirection: .rtl,
                  style: TextStyle(color: Colors.red.shade700),
                )
              else if (_lastReason == 'qr_code_expired')
                Column(
                  children: [
                    const Text(
                      'بارکد پرداخت منقضی شده است. لطفاً دوباره تلاش کنید.',
                      textDirection: .rtl,
                      style: TextStyle(color: Colors.red),
                    ),
                    TextButton(
                      onPressed: _expireQrAndLeave,
                      child: const Text('بازگشت'),
                    ),
                  ],
                )
              else if (_lastReason != null)
                Text(
                  'در انتظار رسید پرداخت...',
                  textDirection: .rtl,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              const SizedBox(height: 24),
              // Same "لغو تراکنش" button as the card swipe / phone payment
              // pages.
              SizedBox(
                child: ElevatedButton(
                  onPressed: _cancelTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('لغو تراکنش'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Phone payment: the QR code plus the polling status.
  Widget _buildQrSection() {
    final url = widget.paymentUrl;
    return Column(
      children: [
        if (url != null && url.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(data: url, size: 220, backgroundColor: Colors.white),
          )
        else
          const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          'لطفا بارکد پرداخت خود را اسکن کنید.',
          textAlign: TextAlign.center,
          textDirection: .rtl,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'پس از پرداخت، سفارش شما به صورت خودکار ثبت می شود.',
          textAlign: TextAlign.center,
          textDirection: .rtl,
          style: TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  // Card / NFC payment: the order is being paid in the new tab, so this page
  // only waits for the records to show up.
  Widget _buildWaitingSection() {
    return Column(
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_cafe_rounded,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 40),
        Text(
          _waitingMessage(),
          textAlign: TextAlign.center,
          textDirection: .rtl,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// Distinguishes waiting for a purchase from waiting for a wallet top-up.
  String _waitingMessage() {
    switch (widget.mode) {
      case OrderLoadingMode.awaitWalletTopUp:
        return 'در انتظار افزایش اعتبار کیف پول...';
      case OrderLoadingMode.awaitPurchase:
        return 'در انتظار ثبت خرید کارتخوان...';
      case OrderLoadingMode.showQrCode:
        return 'در انتظار پرداخت...';
    }
  }

  Widget _buildCountdown() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return Column(
      children: [
        Text(
          'زمان باقی مانده: ${persianFormatter.format(minutes)}:${persianFormatter.format(seconds).padLeft(2, '٠')}',
          textDirection: .rtl,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        // Progress of the 3 minute window.
        SizedBox(
          width: 220,
          child: LinearProgressIndicator(
            value:
                1 -
                (_remainingSeconds / OrderLoadingPage.timeout.inSeconds),
          ),
        ),
      ],
    );
  }

  // Bottom navigation: left (cancel) - OK (cancel) - right (no-op)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: leave the waiting screen
            IconButton.filledTonal(
              onPressed: _cancelTransaction,
              icon: const Icon(
                Icons.subdirectory_arrow_left,
                color: Colors.red,
              ),
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 16),

            // OK button: leave the waiting screen
            GestureDetector(
              onTapUp: (_) => _onOkPressUp(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, size: 24, color: colorScheme.onPrimary),
              ),
            ),
            const SizedBox(width: 16),

            // Right button: no action on this page
            IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'گزینه بعدی',
            ),
          ],
        ),
      ),
    );
  }
}
