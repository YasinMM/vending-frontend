import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class CardSwipePage extends ConsumerStatefulWidget {
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

  // Long-press detection for the OK button
  Timer? _okLongPressTimer;
  bool _okLongPressTriggered = false;

  bool get _isDepositMode => widget.isDepositMode;

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
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedDiscountCodes = ref
        .read(activeDiscountsProvider)
        .where((d) => d.selected)
        .map((d) => d.code)
        .toList();

    return {
      "discount_codes": selectedDiscountCodes,
      "machine_serial": ref.read(activeMachineProvider),
      "product_serials": selectedProducts.map((p) => p.serial).toList(),
      "quantities": selectedProducts.map((p) => p.quantity).toList(),
    };
  }

  Map<String, dynamic> _buildWalletPurchaseData() {
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedDiscountCodes = ref
        .read(activeDiscountsProvider)
        .where((d) => d.selected)
        .map((d) => d.code)
        .toList();

    return {
      "creation_date": DateTime.now().toIso8601String(),
      "discount_codes": selectedDiscountCodes,
      "user": ref.read(activeUserProvider),
      "machine_serial": ref.read(activeMachineProvider),
      "amount": widget.purchaseAmount,
      "product_serials": selectedProducts.map((p) => p.serial).toList(),
      "quantities": selectedProducts.map((p) => p.quantity).toList(),
    };
  }

  Future<void> createWalletDeposit() async {
    await ProductService.depositToWallet({
      "creation_date": DateTime.now().toIso8601String(),
      "user": ref.read(activeUserProvider),
      "bank_serial": "123456",
      "amount": widget.depositAmount,
    });
    await ProductService.createUserWalletPurchase(_buildWalletPurchaseData());
  }

  Future<void> _loadCalculatedAmount() async {
    final amount = await calculateFinalRawPrice(_buildPriceRequestData());
    if (!mounted) {
      return;
    }

    setState(() {
      _calculatedAmount = amount;
    });
  }

  Future<bool> createCardPurchaseTransaction() async {
    int user = ref.read(activeUserProvider);
    String machineSerial = ref.read(activeMachineProvider);

    List<String> productSerials = [];
    List<int> quantities = [];

    final selectedProducts = ref.read(selectedProductsProvider);

    for (Product product in selectedProducts) {
      productSerials.add(product.serial);
      quantities.add(product.quantity);
    }

    final selectedDiscountCodes = ref
        .watch(activeDiscountsProvider)
        .where((d) => d.selected)
        .map((d) => d.code)
        .toList();

    final calculatedAmount = await calculateFinalRawPrice(
      _buildPriceRequestData(),
    );

    if (user == -1) {
      await ProductService.createCardPurchaseTransaction({
        "creation_date": DateTime.now().toIso8601String(),
        "discount_codes": selectedDiscountCodes,
        "bank_serial": "234556",
        "machine_serial": machineSerial,
        "amount": calculatedAmount,
        "product_serials": productSerials,
        "quantities": quantities,
      });
    } else {
      await ProductService.createUserCardPurchaseTransaction({
        "creation_date": DateTime.now().toIso8601String(),
        "discount_codes": selectedDiscountCodes,
        "user": user,
        "bank_serial": "234556",
        "machine_serial": machineSerial,
        "amount": calculatedAmount,
        "product_serials": productSerials,
        "quantities": quantities,
      });
    }

    return true;
  }

  @override
  void initState() {
    super.initState();

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
      _calculatedAmount = widget.depositAmount;
    } else {
      _loadCalculatedAmount();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _okLongPressTimer?.cancel();
    super.dispose();
  }

  // Starts the 1-second long-press timer for the OK button.
  // Holding longer than 1 second acts as the back button.
  void _onOkPressDown() {
    _okLongPressTriggered = false;
    _okLongPressTimer = Timer(const Duration(milliseconds: 1000), () {
      _okLongPressTriggered = true;
      if (mounted) {
        context.pop();
      }
    });
  }

  void _onOkPressUp() {
    _okLongPressTimer?.cancel();
    _okLongPressTimer = null;
    if (!_okLongPressTriggered) {
      _cancelTransaction();
    }
  }

  // OK tap acts like the "لغو تراکنش" button on this page
  void _cancelTransaction() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                _calculatedAmount == null || _calculatedAmount == -1
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
                onPressed: () async {
                  if (_isDepositMode) {
                    await createWalletDeposit();
                  } else {
                    await createCardPurchaseTransaction();
                  }
                  if (mounted) {
                    context.go("/transaction_success");
                  }
                },
                child: Text("کردم"),
              ),
              const SizedBox(height: 12),
              SizedBox(
                child: ElevatedButton(
                  onPressed: () => context.pop(),
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

  // Bottom navigation: left (no-op) - OK (confirm) - right (no-op)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: no action on this page
            IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.arrow_back),
              tooltip: 'گزینه قبلی',
            ),
            const SizedBox(width: 16),

            // OK button: confirm / done.
            // Holding for more than 1 second cancels the transaction.
            GestureDetector(
              onTapDown: (_) => _onOkPressDown(),
              onTapUp: (_) => _onOkPressUp(),
              onTapCancel: () {
                _okLongPressTimer?.cancel();
                _okLongPressTimer = null;
              },
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
