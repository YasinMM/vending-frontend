import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TransactionSuccessPage extends ConsumerStatefulWidget {
  const TransactionSuccessPage({super.key});

  @override
  ConsumerState<TransactionSuccessPage> createState() =>
      _TransactionSuccessPageState();
}

class _TransactionSuccessPageState
    extends ConsumerState<TransactionSuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _floatAnimation;

  // Long-press detection for the OK button
  Timer? _okLongPressTimer;
  bool _okLongPressTriggered = false;

  @override
  void initState() {
    super.initState();

    // Controller for the looping floating animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Scale animation for entrance effect
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    // Subtle up-and-down floating translation
    _floatAnimation = Tween<double>(
      begin: -8.0,
      end: 8.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _okLongPressTimer?.cancel();
    super.dispose();
  }

  // Starts the 1-second long-press timer for the OK button.
  // Holding longer than 1 second also returns home.
  void _onOkPressDown() {
    _okLongPressTriggered = false;
    _okLongPressTimer = Timer(const Duration(milliseconds: 1000), () {
      _okLongPressTriggered = true;
      _goHome();
    });
  }

  void _onOkPressUp() {
    _okLongPressTimer?.cancel();
    _okLongPressTimer = null;
    if (!_okLongPressTriggered) {
      _goHome();
    }
  }

  // OK acts like the "بازگشت" button on this page
  void _goHome() {
    ref.read(activeUserProvider.notifier).setUser(-1); // Reset the active user to -1
    ref.read(selectedProductsProvider.notifier).setProducts([]); // Clear selected products (also resets the product page steps)
    context.go("/");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Coffee Icon with floating effect
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _floatAnimation.value),
                    child: child,
                  );
                },
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade50,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.brown.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.local_cafe_rounded,
                      size: 90,
                      color: Colors.brown.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Success Headline
              Text(
                "تراکنش موفق!",
                textDirection: .rtl,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.brown.shade900,
                ),
              ),
              const SizedBox(height: 12),

              // Subtitle / Details
              Text(
                "سفارش شما در حال آماده سازی است...",
                textDirection: .rtl,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.brown.shade600),
              ),
              const SizedBox(height: 64),

              // Done / Home Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.brown.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _goHome,
                  child: const Text(
                    "بازگشت",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
            // Holding for more than 1 second also returns home.
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
