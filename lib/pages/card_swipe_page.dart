import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/data/classes/card_payment_payload.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Card reader page. Runs in its own browser tab, opened by the waiting page
/// once the order is finalized.
///
/// The order travels in the URL (see [CardPaymentPayload]), because this tab
/// is a separate app instance without the main tab's Riverpod state. The
/// confirm button only creates the corresponding records; the waiting page in
/// the main tab picks them up and moves on.
class CardSwipePage extends ConsumerStatefulWidget {
  /// Route of the card reader page. The waiting page builds this route with
  /// the order encoded in the query string to open it in a new tab.
  static const String routePath = '/card_swipe';

  final int? depositAmount;
  final int? purchaseAmount;

  const CardSwipePage({
    super.key,
    this.depositAmount,
    this.purchaseAmount,
  });

  bool get isDepositMode => depositAmount != null && purchaseAmount != null;

  @override
  ConsumerState<CardSwipePage> createState() => _CardSwipePageState();
}

class _CardSwipePageState extends ConsumerState<CardSwipePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  final persianFormatter = NumberFormat.decimalPattern('fa');
  int? _calculatedAmount;

  // Loading indicators for network requests
  bool _isLoadingAmount = false;
  bool _isCreatingTransaction = false;
  bool _isDepositing = false;

  // True once the records have been created. The page then stays put and only
  // reports success; the waiting page in the main tab takes over.
  bool _isDone = false;

  // Whether the confirm button is busy with any payment request
  bool get _isConfirmingPayment => _isCreatingTransaction || _isDepositing;

  /// The order this tab has to pay for, taken from the URL. Null when the
  /// page was opened without order data (e.g. by hand).
  CardPaymentPayload? _payload;

  bool get _isDepositMode => _payload?.isWalletTopUp ?? widget.isDepositMode;

  /// The amount shown to the customer: the top-up amount in deposit mode,
  /// otherwise the purchase amount.
  int? get _displayAmount => _isDepositMode
      ? (_payload?.depositAmount ?? widget.depositAmount)
      : (_payload?.purchaseAmount ?? _payload?.amount);

  Future<int> calculateFinalRawPrice(Map<String, dynamic> data) async {
    try {
      final response = await ProductService.getFinalPriceFromList(data);
      if (response.data.length != 0) {
        return response.data["data"];
      } else {
        return -1;
      }
    } on DioException {
      return -1;
    }
  }

  Map<String, dynamic> _buildPriceRequestData() {
    final payload = _payload;
    if (payload != null) {
      return {
        "discount_codes": payload.discountCodes,
        "machine_serial": payload.machineSerial,
        "product_serials": payload.productSerials,
        "quantities": payload.quantities,
      };
    }
    // Fallback for the in-app navigation without a payload.
    return {
      "discount_codes": const <String>[],
      "machine_serial": "",
      "product_serials": const <String>[],
      "quantities": const <int>[],
    };
  }

  // Body of the purchase created by a wallet top-up.
  Map<String, dynamic> _buildWalletPurchaseData(CardPaymentPayload payload) {
    return {
      "creation_date": payload.creationDate,
      "discount_codes": payload.discountCodes,
      "user": payload.user,
      "machine_serial": payload.machineSerial,
      "amount": payload.purchaseAmount,
      "product_serials": payload.productSerials,
      "quantities": payload.quantities,
    };
  }

  // Creates a wallet top-up and the purchase it pays for.
  Future<void> createWalletDeposit(CardPaymentPayload payload) async {
    setState(() {
      _isDepositing = true;
    });
    try {
      await ProductService.depositToWallet({
        "creation_date": payload.creationDate,
        "user": payload.user,
        "bank_serial": payload.bankSerial,
        "amount": payload.depositAmount,
      });
      await ProductService.createUserWalletPurchase(
        _buildWalletPurchaseData(payload),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDepositing = false;
        });
      }
    }
  }

  // Creates the card purchase for the order.
  Future<void> createCardPurchaseTransaction(CardPaymentPayload payload) async {
    setState(() {
      _isCreatingTransaction = true;
    });
    try {
      final body = <String, dynamic>{
        "creation_date": payload.creationDate,
        "discount_codes": payload.discountCodes,
        "bank_serial": payload.bankSerial,
        "machine_serial": payload.machineSerial,
        "amount": payload.amount,
        "product_serials": payload.productSerials,
        "quantities": payload.quantities,
      };

      if (payload.user == -1) {
        await ProductService.createCardPurchaseTransaction(body);
      } else {
        await ProductService.createUserCardPurchaseTransaction({
          ...body,
          "user": payload.user,
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingTransaction = false;
        });
      }
    }
  }

  Future<void> _loadCalculatedAmount() async {
    setState(() {
      _isLoadingAmount = true;
    });
    final amount = await calculateFinalRawPrice(_buildPriceRequestData());
    if (!mounted) {
      return;
    }

    setState(() {
      _calculatedAmount = amount;
      _isLoadingAmount = false;
    });
  }

  @override
  void initState() {
    super.initState();

    // The order comes from the URL: this page runs in its own tab, which has
    // no access to the main tab's Riverpod state.
    _payload = CardPaymentPayload.fromUrl();

    // Set up the animation controller for a 1.5-second loop
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Create a curved scale animation (from 1.0 to 1.15)
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (_isDepositMode) {
      _calculatedAmount = _displayAmount;
    } else if (_payload != null && _payload!.amount != null) {
      // The amount was already calculated by the waiting page.
      _calculatedAmount = _payload!.amount;
    } else {
      _loadCalculatedAmount();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Back action (left button): cancels the transaction (same as the
  // previous OK long-press behavior).
  void _goBack() {
    if (_isDone) {
      return;
    }
    _cancelTransaction();
  }

  void _onOkPressUp() {
    if (_isDone) {
      return;
    }
    _cancelTransaction();
  }

  // OK tap acts like the "لغو تراکنش" button on this page
  void _cancelTransaction() {
    // This page can be opened as a standalone tab, where there is nothing to
    // pop back to; fall back to the products page in that case.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go("/");
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      show: _isLoadingAmount || _isConfirmingPayment,
      message: _isConfirmingPayment
          ? 'در حال ثبت تراکنش...'
          : 'در حال محاسبه مبلغ...',
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isDepositMode ? 'افزایش اعتبار کیف پول' : 'پرداخت با کارتخوان'),
          centerTitle: true,
        ),
        body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Looping animated card icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.credit_card_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Instruction text
              Text(
                "لطفا کارت خود را وارد دستگاه کارتخوان کنید.",
                textAlign: TextAlign.center,
                textDirection: .rtl,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Supporting subtitle
              Text(
                _isDepositMode
                  ? "لطفا مبلغ افزایش اعتبار را با کارت پرداخت کنید."
                  : "از کارتخوان متصل به دستگاه استفاده کنید.",
                textAlign: TextAlign.center,
                textDirection: .rtl,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 20),
              Text(
                _isLoadingAmount
                    ? 'مبلغ: در حال محاسبه...'
                    : _calculatedAmount == null || _calculatedAmount == -1
                    ? 'مبلغ افزایش اعتبار: --'
                    : _isDepositMode
                    ? 'مبلغ افزایش اعتبار: ${persianFormatter.format(_calculatedAmount! / 10)} تومان'
                    : 'مبلغ نهایی: ${persianFormatter.format(_calculatedAmount! / 10)} تومان',
                textDirection: .rtl,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 36),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isConfirmingPayment || _isDone || _payload == null
                    ? null
                    : () async {
                  final payload = _payload;
                  if (payload == null) {
                    return;
                  }
                  if (_isDepositMode) {
                    await createWalletDeposit(payload);
                  } else {
                    await createCardPurchaseTransaction(payload);
                  }
                  // Only the records are created here. The waiting page in
                  // the main tab polls for them and moves on, so this tab
                  // must not navigate anywhere.
                  if (mounted) {
                    setState(() {
                      _isDone = true;
                    });
                  }
                },
                child: _isConfirmingPayment
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isDone ? "ثبت شد" : "کردم"),
              ),
              const SizedBox(height: 12),
              SizedBox(
                child: ElevatedButton(
                  onPressed: _isDone ? null : _cancelTransaction,
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
      bottomNavigationBar: _isDone ? null : _buildBottomNavBar(),
      ),
    );
  }

  // Bottom navigation: left (no-op) - OK (confirm) - right (no-op)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: cancel / back
            IconButton.filledTonal(
              onPressed: _goBack,
              icon: const Icon(Icons.subdirectory_arrow_left, color: Colors.red),
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 16),

            // OK button: confirm / done.
            GestureDetector(
              onTapUp: (_) => _onOkPressUp(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  size: 24,
                  color: colorScheme.onPrimary,
                ),
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
