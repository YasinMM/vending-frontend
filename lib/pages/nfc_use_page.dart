import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class NfcUsePage extends ConsumerStatefulWidget {
  const NfcUsePage({super.key});

  @override
  ConsumerState<NfcUsePage> createState() => _NfcUsePageState();
}

class _NfcUsePageState extends ConsumerState<NfcUsePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  // Loading indicator for network requests
  bool _isLoadingDiscounts = false;

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

  Future<List<Discount>> setUserMachineDiscounts() async {
    setState(() {
      _isLoadingDiscounts = true;
    });
    try {
      final serial = ref.read(activeMachineProvider);
      final response = await ProductService.getUserMachineDiscountList(
        serial,
        ref.read(activeUserProvider),
      );
      if (response.data.length != 0) {
        ref.read(activeDiscountsProvider).clear();
        List<Discount> discounts = [];
        for (Map<String, dynamic> d in response.data) {
          var machineSerials = List<String>.from(d["machine_serials"]);
          discounts.add(
            Discount(
              id: d["id"],
              code: d["code"],
              name: d["name"],
              companySharePercentage: d["company_share_percentage"],
              numericAmount: d["numeric_amount"],
              percentageAmount: d["percentage_amount"],
              percentageAmountLimit: d["percentage_amount_limit"],
              startDate: DateTime.parse(d["start_date"]),
              quantityLimit: d["quantity_limit"],
              perUserLimit: d["per_user_limit"],
              machineLimit: d["machine_limit"],
              machineSerials: machineSerials,
              productLimit: d["product_limit"],
              productSerials: List<String>.from(d["product_serials"]),
              isActive: d["is_active"],
              description: d["description"],
              pinned: (machineSerials.contains(serial)) ? d["is_pinned"][machineSerials.indexOf(serial)] : false,
            ),
          );
        }
        ref.read(activeDiscountsProvider.notifier).setDiscounts(discounts);
        return discounts;
      } else {
        ref.read(activeDiscountsProvider.notifier).setDiscounts([]);
        return [];
      }
    } on DioException {
      return [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDiscounts = false;
        });
      }
    }
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

  // Back action (left button): goes back to the products page (same as the
  // previous OK long-press behavior).
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
    return LoadingOverlay(
      show: _isLoadingDiscounts,
      message: 'در حال دریافت اطلاعات کاربر...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پرداخت با شاتکارت'),
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
                    Icons.contact_emergency,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              
              // Instruction text
              Text(
                "لطفا شاتکارت خود را روی گیرنده قرار دهید.",
                textAlign: TextAlign.center,
                textDirection: .rtl,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 36),

              ElevatedButton(
                onPressed: _isLoadingDiscounts
                    ? null
                    : () async {
                  ref.read(activeUserProvider.notifier).setUser(1);
                  await setUserMachineDiscounts();
                  if(mounted){
                    context.push("/discounts");
                  }
                },
                child: _isLoadingDiscounts
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text("کاربر 1"),
              ),

              ElevatedButton(
                onPressed: _isLoadingDiscounts
                    ? null
                    : () async {
                  ref.read(activeUserProvider.notifier).setUser(2);
                  await setUserMachineDiscounts();
                  if(mounted){
                    context.push("/discounts");
                  }
                },
                child: _isLoadingDiscounts
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text("کاربر 2"),
              ),

              ElevatedButton(
                onPressed: _isLoadingDiscounts
                    ? null
                    : () async {
                  ref.read(activeUserProvider.notifier).setUser(3);
                  await setUserMachineDiscounts();
                  if(mounted){
                    context.push("/discounts");
                  }
                },
                child: _isLoadingDiscounts
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text("کاربر 3"),
              ),
              const SizedBox(height: 24),
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
            // Left button: back to the products page
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