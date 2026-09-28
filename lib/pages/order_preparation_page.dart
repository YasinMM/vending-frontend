import 'package:flutter/material.dart';
import 'package:flutter_production_test/data/classes/receipt_batch.dart';
import 'package:flutter_production_test/providers/active_user_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Shows what the machine is doing to prepare the finalized order.
///
/// The order itself is derived from the [ReceiptBatch] the loading page
/// polled for. The actual machine actions (steps of the preparation) are not
/// implemented yet, so the page currently lists the ordered products and
/// provides the usual "back / OK / next" navigation.
class OrderPreparationPage extends ConsumerStatefulWidget {
  /// Route of the preparation page, also used as the exit destination.
  static const String routePath = '/order_preparation';

  final ReceiptBatch batch;

  const OrderPreparationPage({super.key, required this.batch});

  @override
  ConsumerState<OrderPreparationPage> createState() =>
      _OrderPreparationPageState();
}

class _OrderPreparationPageState extends ConsumerState<OrderPreparationPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  final persianFormatter = NumberFormat.decimalPattern('fa');

  @override
  void initState() {
    super.initState();

    // Same looping animation used by the other kiosk pages.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Finishing the preparation resets the order and returns to the first step.
  void _finish() {
    ref.read(activeUserProvider.notifier).setUser(-1);
    ref.read(selectedProductsProvider.notifier).setProducts([]);
    context.go("/");
  }

  // Back also leaves the preparation. This page is pushed on top of the
  // waiting page, whose timers are already stopped, so popping would return
  // to a dead screen — the same reset as OK is used instead.
  void _goBack() {
    _finish();
  }

  // The main drink, shown on its own with "تک" / "دوبل".
  ReceiptBatchItem? get _mainItem {
    for (final item in widget.batch.items) {
      if (item.isMainProduct) {
        return item;
      }
    }
    return null;
  }

  // Everything that is not the main drink, minus the cup: the cup is not a
  // product the machine adds, it only indicates a vessel choice.
  List<ReceiptBatchItem> get _addonItems => widget.batch.items
      .where((item) => !item.isMainProduct && item.productSerial != _cupSerial)
      .toList();

  /// Whether the customer brought their own cup.
  ///
  /// The receipt only contains a `cup` line when the machine cup was
  /// *chosen*: the "use my own cup" option (`no__cup`) is never sent to the
  /// backend, so it produces no receipt at all. The message is therefore shown
  /// when the cup is **absent** from the batch.
  bool get _usesOwnCup => !widget.batch.items.any(
    (item) => item.productSerial == _cupSerial,
  );

  static const String _cupSerial = 'cup';

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    final mainItem = _mainItem;
    final addons = _addonItems;

    return Scaffold(
      appBar: AppBar(title: const Text('آماده سازی سفارش'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
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
                    Icons.local_cafe_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'در حال آماده سازی سفارش شما...',
                textAlign: TextAlign.center,
                textDirection: .rtl,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'شماره رسید: ${batch.serial}',
                textDirection: .rtl,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),

              // The customer brought their own cup: ask them to place it.
              if (_usesOwnCup) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_drink,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'لطفا لیوان خود را در جایگاه قرار دهید.',
                          textDirection: .rtl,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Ordered products: the main drink, then the add-ons below it,
              // each separated by a plus icon.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    if (mainItem != null)
                      _buildProductTile(
                        mainItem,
                        // The main drink is shown as "تک" / "دوبل" rather
                        // than a raw quantity.
                        subtitle: mainItem.quantity >= 2 ? 'دوبل' : 'تک',
                      ),
                    for (final addon in addons) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Icon(Icons.add, size: 20, color: Colors.grey),
                      ),
                      // Add-ons are always a single unit, so no quantity.
                      _buildProductTile(addon),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'مبلغ نهایی: ${persianFormatter.format(batch.totalPrice / 10)} تومان',
                textDirection: .rtl,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // One product line in the order list. [subtitle] is omitted for add-ons,
  // which carry no quantity, and no price is shown on any line.
  Widget _buildProductTile(ReceiptBatchItem item, {String? subtitle}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: const Icon(Icons.local_cafe),
        title: Text(item.productName, textDirection: .rtl),
        subtitle: subtitle == null
            ? null
            : Text(subtitle, textDirection: .rtl),
      ),
    );
  }

  // Bottom navigation: left (back) - OK (done) - right (done)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: back
            IconButton.filledTonal(
              onPressed: _goBack,
              icon: const Icon(
                Icons.subdirectory_arrow_left,
                color: Colors.red,
              ),
              tooltip: 'بازگشت',
            ),
            const SizedBox(width: 16),

            // OK button: the preparation is finished
            GestureDetector(
              onTapUp: (_) => _finish(),
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

            // Right button: next (no further steps implemented yet)
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
