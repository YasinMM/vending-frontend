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

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;

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
              const SizedBox(height: 32),

              // The ordered products of this batch.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    for (final item in batch.items)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.local_cafe),
                          title: Text(
                            item.productName,
                            textDirection: .rtl,
                          ),
                          subtitle: Text(
                            'تعداد: ${item.quantity}',
                            textDirection: .rtl,
                          ),
                          trailing: Text(
                            '${persianFormatter.format(item.finalPrice / 10)} تومان',
                            textDirection: .rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
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
              onPressed: () => context.pop(),
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
