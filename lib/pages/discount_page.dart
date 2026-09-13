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

class DiscountPage extends ConsumerStatefulWidget {
  const DiscountPage({super.key});

  @override
  ConsumerState<DiscountPage> createState() => _DiscountPageState();
}

class _DiscountPageState extends ConsumerState<DiscountPage> {
  final persianFormatter = NumberFormat.decimalPattern('fa');

  // A sample list of different discount options
  List<Discount> _discounts = [];

  // Tracks the currently selected discount IDs using a Set for multiple selections
  final Set<String> _selectedDiscountCodes = {};
  int? _finalPrice;
  int? _walletBalance;

  // Long-press detection for the OK button
  Timer? _okLongPressTimer;
  bool _okLongPressTriggered = false;

  // Index of the currently highlighted option. Options are the discounts
  // followed by one extra "confirm" pseudo-option at the end.
  int _selectedOptionIndex = 0;

  // Selected payment button on the bottom (index into _paymentActions)
  int _selectedPaymentIndex = 0;
  bool _paymentMode = false; // true when selection hovers the bottom buttons

  bool _isDiscountAvailable(
    Discount discount,
    Set<String> selectedProductSerials,
  ) {
    if (!discount.productLimit || discount.productSerials.isEmpty) {
      return true;
    }

    return selectedProductSerials.any(
      (serial) => discount.productSerials.contains(serial),
    );
  }

  Future<int> calculateFinalPrice(Map<String, dynamic> data) async {
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

  Future<void> _updateFinalPrice(List<Product> selectedProducts) async {
    final finalPrice = await calculateFinalPrice({
      'discount_codes': _selectedDiscountCodes.toList(),
      'machine_serial': ref.read(activeMachineProvider),
      'product_serials': selectedProducts
          .map((product) => product.serial)
          .toList(),
      'quantities': selectedProducts
          .map((product) => product.quantity)
          .toList(),
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _finalPrice = finalPrice;
    });
  }

  Future<void> _loadWalletBalance() async {
    final user = ref.read(activeUserProvider);
    if (user == -1) {
      return;
    }

    try {
      final response = await ProductService.getWalletByUser(user);
      final data = response.data;
      final balance = data is Map ? data['balance'] : data;

      if (!mounted) {
        return;
      }

      setState(() {
        _walletBalance = balance is num ? balance.toInt() : null;
      });
    } on DioException {
      if (!mounted) {
        return;
      }

      setState(() {
        _walletBalance = null;
      });
    }
  }

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

    final calculatedAmount = await calculateFinalRawPrice({
      "discount_codes": selectedDiscountCodes,
      "machine_serial": machineSerial,
      "product_serials": productSerials,
      "quantities": quantities,
    });

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
    _updateFinalPrice(ref.read(selectedProductsProvider));
    _loadWalletBalance();
  }

  @override
  void dispose() {
    _okLongPressTimer?.cancel();
    super.dispose();
  }

  // Moves the highlight to the next option (discounts, then payment buttons).
  // Skips over disabled (unavailable) discounts.
  void _selectNextOption(int discountCount, List<Discount> orderedDiscounts) {
    setState(() {
      if (!_paymentMode) {
        if (_selectedOptionIndex < discountCount) {
          _selectedOptionIndex++;
          _skipUnavailableDiscounts(orderedDiscounts, discountCount, forward: true);
        }
      } else {
        _selectedPaymentIndex =
            (_selectedPaymentIndex + 1) % _paymentButtonCount;
      }
    });
  }

  // Moves the highlight to the previous option.
  // Wraps around from the first option to the last, and skips
  // over disabled (unavailable) discounts.
  void _selectPreviousOption(
    int discountCount,
    List<Discount> orderedDiscounts,
  ) {
    setState(() {
      if (_paymentMode) {
        if (_selectedPaymentIndex > 0) {
          _selectedPaymentIndex--;
        } else {
          // Back to the confirm pseudo-option
          _paymentMode = false;
          _selectedOptionIndex = discountCount;
        }
      } else {
        // Wrap around: first option goes back to the last option
        // (the confirm pseudo-option when at index 0)
        if (_selectedOptionIndex == 0) {
          _selectedOptionIndex = discountCount;
        } else {
          _selectedOptionIndex--;
          _skipUnavailableDiscounts(
            orderedDiscounts,
            discountCount,
            forward: false,
          );
        }
      }
    });
  }

  // Moves the highlight past unavailable discounts in the given direction
  void _skipUnavailableDiscounts(
    List<Discount> orderedDiscounts,
    int discountCount, {
    required bool forward,
  }) {
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedProductSerials = selectedProducts
        .map((p) => p.serial)
        .toSet();

    // The confirm pseudo-option is always selectable
    if (_selectedOptionIndex >= discountCount) {
      return;
    }

    int attempts = 0;
    while (attempts < discountCount &&
        _selectedOptionIndex < discountCount &&
        !_isDiscountAvailable(
          orderedDiscounts[_selectedOptionIndex],
          selectedProductSerials,
        )) {
      if (forward) {
        if (_selectedOptionIndex >= discountCount) {
          break;
        }
        _selectedOptionIndex++;
      } else {
        if (_selectedOptionIndex == 0) {
          _selectedOptionIndex = discountCount;
          break;
        }
        _selectedOptionIndex--;
      }
      attempts++;
    }
  }

  // Confirms the highlighted option: toggles a discount, enters payment
  // mode on the confirm option, or triggers the highlighted payment button.
  void _confirmSelection(List<Discount> orderedDiscounts) {
    if (_paymentMode) {
      _triggerPaymentButton(_selectedPaymentIndex, orderedDiscounts);
      return;
    }

    // The last option is the "confirm" pseudo-option
    if (_selectedOptionIndex >= orderedDiscounts.length) {
      setState(() {
        _paymentMode = true;
        _selectedPaymentIndex = 0;
      });
      return;
    }

    // Toggle the highlighted discount
    final discount = orderedDiscounts[_selectedOptionIndex];
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedProductSerials = selectedProducts
        .map((p) => p.serial)
        .toSet();

    if (_isDiscountAvailable(discount, selectedProductSerials)) {
      setState(() {
        if (_selectedDiscountCodes.contains(discount.code)) {
          _selectedDiscountCodes.remove(discount.code);
        } else {
          _selectedDiscountCodes.add(discount.code);
        }
      });
      _updateFinalPrice(selectedProducts);
    }
  }

  // Starts the 1-second long-press timer for the OK button.
  // In discount mode: goes back to the products page.
  // In payment mode: moves the selection back to the discounts grid.
  void _onOkPressDown() {
    _okLongPressTriggered = false;
    _okLongPressTimer = Timer(const Duration(milliseconds: 1000), () {
      _okLongPressTriggered = true;
      if (!mounted) {
        return;
      }
      if (_paymentMode) {
        setState(() {
          _paymentMode = false;
          _selectedOptionIndex = 0;
        });
      } else {
        context.go("/");
      }
    });
  }

  void _onOkPressUp(List<Discount> orderedDiscounts) {
    _okLongPressTimer?.cancel();
    _okLongPressTimer = null;
    if (!_okLongPressTriggered) {
      _confirmSelection(orderedDiscounts);
    }
  }

  // Number of payment buttons currently visible at the bottom
  int get _paymentButtonCount {
    int count = 0;
    if (_finalPrice == 0) {
      count = 1; // تکمیل سفارش
    } else {
      count = 1; // پرداخت با کارت
      if (ref.read(activeUserProvider) != -1) {
        count++; // کیف پول
      }
    }
    return count;
  }

  // Whether the payment button at the given index is enabled
  bool _isPaymentButtonEnabled(int index) {
    if (_finalPrice == 0) {
      return true; // تکمیل سفارش
    }
    if (index == 0) {
      return true; // پرداخت با کارت
    }
    // کیف پول / افزایش اعتبار
    return _walletBalance != null && _finalPrice != null && _walletBalance! > 0;
  }

  // Triggers the payment button at the given index (same actions as tapping)
  Future<void> _triggerPaymentButton(
    int index,
    List<Discount> orderedDiscounts,
  ) async {
    // Disabled buttons do nothing
    if (!_isPaymentButtonEnabled(index)) {
      return;
    }

    // Mark the selected discounts before navigating
    final selectedProducts = ref.read(selectedProductsProvider);
    final selectedProductSerials = selectedProducts
        .map((p) => p.serial)
        .toSet();
    final selectedDiscounts = orderedDiscounts
        .where(
          (d) =>
              _selectedDiscountCodes.contains(d.code) &&
              _isDiscountAvailable(d, selectedProductSerials),
        )
        .toList();
    for (final discount in selectedDiscounts) {
      discount.selected = true;
    }

    if (_finalPrice == 0) {
      // تکمیل سفارش
      await createCardPurchaseTransaction();
      if (mounted) {
        context.go("/transaction_success");
      }
      return;
    }

    final walletVisible = ref.read(activeUserProvider) != -1;
    if (index == 0) {
      // پرداخت با کارت
      if (mounted) {
        context.push("/card_swipe");
      }
    } else if (walletVisible && _walletBalance != null && _finalPrice != null) {
      // کیف پول / افزایش اعتبار
      final depositAmount = _finalPrice! - _walletBalance!;
      if (mounted) {
        context.push("/card_swipe", extra: {
          "depositAmount": depositAmount,
          "purchaseAmount": _finalPrice!,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _discounts = ref.watch(activeDiscountsProvider);
    final selectedProductSerials = ref
        .watch(selectedProductsProvider)
        .map((product) => product.serial)
        .toSet();
    final selectedProducts = ref.watch(selectedProductsProvider);

    final orderedDiscounts = [..._discounts]
      ..sort((a, b) {
        final aAvailable = _isDiscountAvailable(a, selectedProductSerials);
        final bAvailable = _isDiscountAvailable(b, selectedProductSerials);

        if (aAvailable != bAvailable) {
          return aAvailable ? -1 : 1;
        }

        if (aAvailable && bAvailable) {
          if (a.pinned != b.pinned) {
            return a.pinned ? -1 : 1;
          }
        }

        return 0;
      });

    return Scaffold(
      appBar: AppBar(title: const Text('تکمیل خرید'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'تخفیف های قابل انتخاب:',
              textDirection: .rtl,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: orderedDiscounts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.local_offer_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'تخفیفی موجود نیست',
                            textDirection: .rtl,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.6, // Shorter cards to avoid scrolling
                ),
                itemCount: orderedDiscounts.length + 1,
                itemBuilder: (context, index) {
                  // Extra trailing item: the "confirm" pseudo-option
                  if (index == orderedDiscounts.length) {
                    final isHighlighted =
                        !_paymentMode &&
                        _selectedOptionIndex == index;
                    return Directionality(
                      textDirection: .rtl,
                      child: Card(
                        color: isHighlighted
                            ? Colors.amber.withValues(alpha: 0.15)
                            : null,
                        elevation: isHighlighted ? 6 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          side: BorderSide(
                            color: isHighlighted
                                ? Colors.amber
                                : Colors.transparent,
                            width: isHighlighted ? 3 : 2,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _paymentMode = true;
                              _selectedPaymentIndex = 0;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 40,
                                  color: isHighlighted
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.green,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'تایید و ادامه',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isHighlighted
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primary
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'رفتن به گزینه های پرداخت',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final discount = orderedDiscounts[index];
                  final isAvailable = _isDiscountAvailable(
                    discount,
                    selectedProductSerials,
                  );
                  final isSelected =
                      isAvailable &&
                      _selectedDiscountCodes.contains(discount.code);
                  final isHighlighted =
                      !_paymentMode && _selectedOptionIndex == index;

                  return Directionality(
                    textDirection: .rtl,
                    child: Opacity(
                      opacity: isAvailable ? 1.0 : 0.55,
                      child: Card(
                        color: isAvailable
                            ? isHighlighted
                                  ? Colors.amber.withValues(alpha: 0.15)
                                  : null
                            : Colors.grey[200],
                        elevation: isSelected || isHighlighted ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          side: BorderSide(
                            color: isHighlighted
                                ? Colors.amber
                                : isSelected
                                ? Theme.of(context).colorScheme.primary
                                : isAvailable
                                ? Colors.transparent
                                : Colors.grey.shade400,
                            width: isHighlighted ? 3 : 2,
                          ),
                        ),
                        child: InkWell(
                          onTap: isAvailable
                              ? () {
                                  setState(() {
                                    if (_selectedDiscountCodes.contains(
                                      discount.code,
                                    )) {
                                      _selectedDiscountCodes.remove(
                                        discount.code,
                                      );
                                    } else {
                                      _selectedDiscountCodes.add(discount.code);
                                    }
                                  });
                                  _updateFinalPrice(selectedProducts);
                                }
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Selection indicator
                                Icon(
                                  isSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 28,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.shade600,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  discount.name,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isAvailable
                                        ? isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Colors.black87
                                        : Colors.black54,
                                  ),
                                ),
                                if (discount.pinned) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'ویژه دستگاه',
                                      textDirection: .rtl,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                                if (discount.description != null &&
                                    discount.description!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        discount.description!,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        textDirection: .rtl,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isAvailable
                                              ? Colors.black54
                                              : Colors.black38,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'کد: ${discount.code}',
                                    textDirection: .rtl,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: isAvailable
                                          ? Colors.black54
                                          : Colors.black38,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _finalPrice == null
                        ? 'قیمت نهایی: --'
                        : _finalPrice == 0
                        ? 'قیمت نهایی: رایگان'
                        : 'قیمت نهایی: ${persianFormatter.format(_finalPrice! / 10)} تومان',
                    textDirection: .rtl,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (_finalPrice == 0)
                        _buildPaymentButton(
                          index: 0,
                          label: 'تکمیل سفارش',
                          color: Colors.green,
                          orderedDiscounts: orderedDiscounts,
                        )
                      else ...[
                        _buildPaymentButton(
                          index: 0,
                          label: 'پرداخت با کارت',
                          color: Colors.deepOrange,
                          orderedDiscounts: orderedDiscounts,
                        ),
                        if (ref.watch(activeUserProvider) != -1)
                          Column(
                            children: [
                              _buildPaymentButton(
                                index: 1,
                                label:
                                    _walletBalance != null &&
                                        _finalPrice != null &&
                                        _walletBalance! > 0 &&
                                        _walletBalance! < _finalPrice!
                                    ? 'افزایش اعتبار'
                                    : 'پرداخت با کیف پول',
                                color: Colors.teal,
                                orderedDiscounts: orderedDiscounts,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _walletBalance == null
                                    ? 'موجودی: --'
                                    : 'موجودی: ${persianFormatter.format(_walletBalance! / 10)} ت',
                                textDirection: .rtl,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(orderedDiscounts),
    );
  }

  // A payment button at the bottom. The highlighted one (via nav buttons)
  // gets a black border, and OK triggers its action.
  Widget _buildPaymentButton({
    required int index,
    required String label,
    required Color color,
    required List<Discount> orderedDiscounts,
  }) {
    final isHighlighted = _paymentMode && _selectedPaymentIndex == index;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        side: BorderSide(
          color: isHighlighted ? Colors.amber : Colors.transparent,
          width: isHighlighted ? 4 : 0,
        ),
        elevation: isHighlighted ? 8 : 2,
      ),
      onPressed: _isPaymentButtonEnabled(index)
          ? () {
              setState(() {
                _paymentMode = true;
                _selectedPaymentIndex = index;
              });
              _triggerPaymentButton(index, orderedDiscounts);
            }
          : null,
      child: Text(label, style: const TextStyle(fontSize: 16, color: Colors.white)),
    );
  }

  // Bottom navigation: left (previous option) - OK (confirm) - right (next option)
  Widget _buildBottomNavBar(List<Discount> orderedDiscounts) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: previous option
            IconButton.filledTonal(
              onPressed: () =>
                  _selectPreviousOption(orderedDiscounts.length, orderedDiscounts),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'گزینه قبلی',
            ),
            const SizedBox(width: 16),

            // OK button: confirm selection.
            // Holding for more than 1 second goes back to the product page.
            GestureDetector(
              onTapDown: (_) => _onOkPressDown(),
              onTapUp: (_) => _onOkPressUp(orderedDiscounts),
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

            // Right button: next option
            IconButton.filledTonal(
              onPressed: () =>
                  _selectNextOption(orderedDiscounts.length, orderedDiscounts),
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'گزینه بعدی',
            ),
          ],
        ),
      ),
    );
  }
}
