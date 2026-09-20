import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

class PhonePaymentPage extends ConsumerStatefulWidget {
  const PhonePaymentPage({super.key});

  @override
  ConsumerState<PhonePaymentPage> createState() => _PhonePaymentPageState();
}

class _PhonePaymentPageState extends ConsumerState<PhonePaymentPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Set up the animation controller for a 1.5-second loop
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Create a curved scale animation (from 1.0 to 1.15)
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Builds the same payload the card payment flow uses, so the online
  // payment tab can create the transaction with fresh app state.
  Map<String, dynamic> _buildOnlinePaymentPayload() {
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
      "bank_serial": "234556",
      "machine_serial": ref.read(activeMachineProvider),
      "product_serials": selectedProducts.map((p) => p.serial).toList(),
      "quantities": selectedProducts.map((p) => p.quantity).toList(),
    };
  }

  // Builds the online payment URL with the order data encoded in the
  // query string (base64 JSON), so the page works in any browser.
  String _buildOnlinePaymentUrl() {
    final payload = jsonEncode(_buildOnlinePaymentPayload());
    final encoded = base64Url.encode(utf8.encode(payload));
    final origin = Uri.base.origin;
    final path = Uri.base.path.replaceFirst(RegExp(r'index\.html$'), '');
    return '$origin${path}#/online_payment?data=$encoded';
  }

  // Opens the online payment page in a new tab/window — the exact same
  // URL the QR code contains.
  void _openOnlinePaymentTab() {
    html.window.open(_buildOnlinePaymentUrl(), 'online_payment');
  }

  // Back action (left button): goes back to the products page.
  void _goBack() {
    if (mounted) {
      context.go("/");
    }
  }

  void _onOkPressUp() {
    _cancelTransaction();
  }

  // OK tap acts like the "لغو تراکنش" button on this page
  void _cancelTransaction() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final paymentUrl = _buildOnlinePaymentUrl();

    return Scaffold(
      appBar: AppBar(
        title: const Text('پرداخت با تلفن همراه'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Looping animated phone icon
              ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.smartphone,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Instruction text
              Text(
                "لطفا بارکد پرداخت خود را اسکن کنید.",
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),

              // QR code containing the online payment URL with the
              // complete order data in its query string.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: paymentUrl,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                child: ElevatedButton(
                  onPressed: _openOnlinePaymentTab,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('انجام شد'),
                ),
              ),
              const SizedBox(height: 12),
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

  // Bottom navigation: left (back) - OK (cancel) - right (no-op)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: back to the products page
            IconButton.filledTonal(
              onPressed: _goBack,
              icon: const Icon(Icons.subdirectory_arrow_left, color: Colors.red),
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 16),

            // OK button: acts like the cancel transaction button.
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
