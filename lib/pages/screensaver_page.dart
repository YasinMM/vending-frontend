import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Attract/screen-saver page shown after the inactivity timeout elapses.
///
/// The user sees an animated coffee icon and the usual three navigation
/// buttons. Pressing any of them dismisses the screensaver and drops the user
/// back at the first step of the order flow, exactly as the old behaviour of
/// navigating to "/" did.
class ScreensaverPage extends ConsumerStatefulWidget {
  const ScreensaverPage({super.key});

  /// Route of the screensaver. Kept in one place so the router and the
  /// inactivity service cannot drift apart.
  static const String routePath = '/screensaver';

  @override
  ConsumerState<ScreensaverPage> createState() => _ScreensaverPageState();
}

class _ScreensaverPageState extends ConsumerState<ScreensaverPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Gentle pulse, matching the loop used on the other kiosk pages.
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Leaves the screensaver: clears the in-progress order and returns to the
  // first step of the product page.
  void _resume() {
    ref.read(activeUserProvider.notifier).setUser(-1);
    ref.read(selectedProductsProvider.notifier).setProducts([]);
    ref.read(activeDiscountsProvider.notifier).setDiscounts([]);
    context.go("/");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حالت استراحت'), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
                  Icons.coffee,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 48),
            const Text(
              'برای شروع سفارش، یکی از دکمه های پایین را بزنید.',
              textAlign: TextAlign.center,
              textDirection: .rtl,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // Bottom navigation: left (back) - OK (resume) - right (resume)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: also resumes the order flow
            IconButton.filledTonal(
              onPressed: _resume,
              icon: const Icon(
                Icons.subdirectory_arrow_left,
                color: Colors.red,
              ),
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 16),

            // OK button: resume
            GestureDetector(
              onTapUp: (_) => _resume(),
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

            // Right button: also resumes the order flow
            IconButton.filledTonal(
              onPressed: _resume,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'گزینه بعدی',
            ),
          ],
        ),
      ),
    );
  }
}
