import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_discounts_notifier_provider.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/providers/selected_products_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/loading_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// Model for an individual choice option
class ChoiceOption {
  final String title;
  final IconData icon;
  final String serial;
  int priceDiff;
  Product? product;

  ChoiceOption({
    required this.title,
    required this.icon,
    required this.serial,
    required this.priceDiff,
    this.product,
  });
}

// Model to hold the data for each choice step
class ChoiceStep {
  final String question;
  final List<ChoiceOption> options;
  final String title;
  String? selectedOption; // Remembers the user's choice
  String? selectedOptionTitle; // Remembers the user's choice

  ChoiceStep({
    required this.question,
    required this.options,
    required this.title,
  });
}

class ProductPage extends ConsumerStatefulWidget {
  const ProductPage({super.key});

  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<ProductPage> {
  final persianFormatter = NumberFormat.decimalPattern('fa');

  final PageController _pageController = PageController();
  int _currentIndex = 0;

  List<String> productSerials = [];
  List<int> quantities = [];

  // Define the sequential choices (now supporting dynamic amounts)
  final List<ChoiceStep> _steps = [];

  // Selected payment option on the summary page (index into _summaryOptions)
  int _selectedSummaryOption = 0;

  // Loading indicators for network requests
  bool _isLoadingProducts = false;
  bool _isStartingPayment = false;

  // Cached final-price request for the summary page. Created once when the
  // user moves past the last step so it isn't re-fetched on every rebuild.
  Future<int>? _finalPriceFuture;

  // Payment options shown on the summary page, treated like regular options
  static const List<String> _summaryOptions = [
    'subscription',
    'nfc',
    'phone',
    'card',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void getMachineProducts(String serial) async {
    setState(() {
      _isLoadingProducts = true;
    });
    try {
      final response = await ProductService.getMachineProductList(serial);

      if (response.data.length != 0) {
        setState(() {
          _steps.clear();
          _steps.add(
            ChoiceStep(
              title: "نوشیدنی",
              question: 'نوشیدنی خود را انتخاب کنید',
              options: [],
            ),
          );
          _steps.add(
            ChoiceStep(
              title: "حجم نوشیدنی",
              question: 'مقدار نوشیدنی را انتخاب کنید',
              options: [
                ChoiceOption(
                  title: 'تکی',
                  icon: Icons.looks_one,
                  serial: "single",
                  priceDiff: 0,
                ),
                ChoiceOption(
                  title: 'دوتایی',
                  icon: Icons.looks_two,
                  serial: "double",
                  priceDiff: 0,
                ),
              ],
            ),
          );
          for (Map<String, dynamic> p in response.data) {
            if (p["type"] == 1) {
              _steps[0].options.add(
                ChoiceOption(
                  title: p["name"],
                  icon: Icons.coffee,
                  serial: p["serial"],
                  priceDiff: p["machine_products__price"],
                  product: Product(
                    id: p["id"],
                    name: p["name"],
                    serial: p["serial"],
                    type: p["type"],
                    companyShare:
                        p["machine_products__contract_machine_product__company_share"],
                    parnterShare:
                        p["machine_products__price"] -
                        p["machine_products__contract_machine_product__company_share"],
                    companyDoubleRate:
                        p["machine_products__contract_machine_product__company_double_rate"],
                    partnerDoubleRate:
                        p["machine_products__contract_machine_product__partner_double_rate"],
                  ),
                ),
              );
            } else if (p["type"] == 2) {
              if (p["serial"] == "cream") {
                _steps.add(
                  ChoiceStep(
                    title: "افزودن خامه",
                    question: 'آیا مایل به افزودن خامه هستید؟',
                    options: [
                      ChoiceOption(
                        title: 'بله اضافه شود',
                        icon: Icons.add,
                        serial: "cream",
                        priceDiff: p["machine_products__price"],
                        product: Product(
                          id: p["id"],
                          name: p["name"],
                          serial: p["serial"],
                          type: p["type"],
                          companyShare:
                              p["machine_products__contract_machine_product__company_share"],
                          parnterShare:
                              p["machine_products__price"] -
                              p["machine_products__contract_machine_product__company_share"],
                          companyDoubleRate:
                              p["machine_products__contract_machine_product__company_double_rate"],
                          partnerDoubleRate:
                              p["machine_products__contract_machine_product__partner_double_rate"],
                          quantity: 1,
                        ),
                      ),
                      ChoiceOption(
                        title: 'خیر تمایل ندارم',
                        icon: Icons.close,
                        serial: "no__cream",
                        priceDiff: 0,
                      ),
                    ],
                  ),
                );
              } else if (p["serial"] == "cup") {
                _steps.add(
                  ChoiceStep(
                    title: "استفاده از لیوان",
                    question: 'آیا از لیوان دستگاه استفاده می‌کنید؟',
                    options: [
                      ChoiceOption(
                        title: 'بله',
                        icon: Icons.local_drink,
                        serial: "cup",
                        priceDiff: p["machine_products__price"],
                        product: Product(
                          id: p["id"],
                          name: p["name"],
                          serial: p["serial"],
                          type: p["type"],
                          companyShare:
                              p["machine_products__contract_machine_product__company_share"],
                          parnterShare:
                              p["machine_products__price"] -
                              p["machine_products__contract_machine_product__company_share"],
                          companyDoubleRate:
                              p["machine_products__contract_machine_product__company_double_rate"],
                          partnerDoubleRate:
                              p["machine_products__contract_machine_product__partner_double_rate"],
                          quantity: 1,
                        ),
                      ),
                      ChoiceOption(
                        title: 'لیوان خودم را استفاده می‌کنم',
                        icon: Icons.coffee,
                        serial: "no__cup",
                        priceDiff: -p["machine_products__price"],
                      ),
                    ],
                  ),
                );
              }
            }
          }
        });
        // First option of the first step is selected by default
        _selectDefaultOption(0);
      }
    } on DioException {
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  Future<List<Discount>> setMachinePinnedDiscounts() async {
    try {
      final serial = ref.read(activeMachineProvider);
      final response = await ProductService.getMachinePinnedDiscountList(
        serial,
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

  @override
  void initState() {
    getMachineProducts(ref.read(activeMachineProvider));
    // Listen for explicit clearing of the selected products (from the
    // transaction success page) and reset the order flow accordingly.
    ref.listenManual(selectedProductsProvider, (previous, next) {
      if (next.isEmpty && (previous?.isNotEmpty ?? false)) {
        _resetOrder();
      }
    });
    super.initState();
  }

  // Selects the first option of the given step by default (if nothing selected)
  void _selectDefaultOption(int stepIndex) {
    if (stepIndex >= 0 && stepIndex < _steps.length) {
      final step = _steps[stepIndex];
      if (step.selectedOption == null && step.options.isNotEmpty) {
        final first = step.options.first;
        step.selectedOption = first.serial;
        step.selectedOptionTitle = first.title;
        // Keep single/double pricing in sync like a manual selection would
        if (stepIndex == 0) {
          _updateDoublePricing(first.serial);
        }
      }
    }
  }

  void _updateDoublePricing(String selectedValue) {
    for (var option in _steps[0].options) {
      if (option.serial == selectedValue) {
        _steps[1].options[0].priceDiff = option.priceDiff;
        _steps[1].options[1].priceDiff =
            (option.product!.companyShare *
                        option.product!.companyDoubleRate +
                    option.product!.parnterShare *
                        option.product!.partnerDoubleRate)
                .floor();
      }
    }
  }

  // Moves the selection to the next option within the current step
  void _selectNextOption() {
    if (_currentIndex >= _steps.length) {
      // Summary page: cycle through payment options
      setState(() {
        _selectedSummaryOption =
            (_selectedSummaryOption + 1) % _summaryOptions.length;
      });
      return;
    }
    final step = _steps[_currentIndex];
    if (step.options.isEmpty) {
      return;
    }
    final currentIdx = step.options.indexWhere(
      (o) => o.serial == step.selectedOption,
    );
    final nextIdx = (currentIdx + 1) % step.options.length;
    final option = step.options[nextIdx];
    setState(() {
      step.selectedOption = option.serial;
      step.selectedOptionTitle = option.title;
      if (_currentIndex == 0) {
        _updateDoublePricing(option.serial);
      }
    });
  }

  // Moves the selection to the previous option within the current step
  void _selectPreviousOption() {
    if (_currentIndex >= _steps.length) {
      // Summary page: cycle through payment options
      setState(() {
        _selectedSummaryOption =
            (_selectedSummaryOption - 1 + _summaryOptions.length) %
                _summaryOptions.length;
      });
      return;
    }
    final step = _steps[_currentIndex];
    if (step.options.isEmpty) {
      return;
    }
    final currentIdx = step.options.indexWhere(
      (o) => o.serial == step.selectedOption,
    );
    final prevIdx =
        (currentIdx - 1 + step.options.length) % step.options.length;
    final option = step.options[prevIdx];
    setState(() {
      step.selectedOption = option.serial;
      step.selectedOptionTitle = option.title;
      if (_currentIndex == 0) {
        _updateDoublePricing(option.serial);
      }
    });
  }

  // Confirms the current selection: advances to the next step,
  // or triggers the selected payment option on the summary page.
  void _confirmSelection() {
    if (_currentIndex < _steps.length) {
      _goToNextPage();
      return;
    }

    // Summary page: OK acts like tapping the selected payment button
    switch (_summaryOptions[_selectedSummaryOption]) {
      case 'nfc':
        finalizeOrder();
        context.push("/nfc_use");
        break;
      case 'card':
        _startCardPayment();
        break;
      case 'subscription':
      case 'phone':
        // Not implemented yet
        break;
    }
  }

  Future<void> _startCardPayment() async {
    setState(() {
      _isStartingPayment = true;
    });
    finalizeOrder();
    final discounts = await setMachinePinnedDiscounts();
    if (!mounted) {
      return;
    }
    setState(() {
      _isStartingPayment = false;
    });
    if (discounts.isNotEmpty) {
      context.push("/discounts");
    } else {
      context.push("/card_swipe");
    }
  }

  // Back action (left button): resets to the first step (same as the
  // previous OK long-press behavior).
  void _goBack() {
    _resetOrder();
  }

  void _onOkPressUp() {
    _confirmSelection();
  }

  void _goToNextPage() {
    if (_currentIndex == _steps.length - 1) {
      setState(() {
        productSerials.clear();
        quantities.clear();
        for (int i = 0; i < _steps.length; i++) {
          for (var option in _steps[i].options) {
            if (option.serial == _steps[i].selectedOption) {
              if (i == 0) {
                productSerials.add(option.serial);
              } else if (i == 1) {
                quantities.add((option.serial == "double") ? 2 : 1);
              } else {
                if (option.serial.indexOf("no__") != 0) {
                  productSerials.add(option.serial);
                  quantities.add(1);
                }
              }
            }
          }
        }

        // Kick off the final price request once, before the summary page
        // becomes visible, so the FutureBuilder doesn't re-create it on
        // every rebuild (which would loop forever and never show a price).
        _finalPriceFuture = calculateFinalRawPrice({
          "discount_codes": [],
          "machine_serial": ref.read(activeMachineProvider),
          "product_serials": productSerials,
          "quantities": quantities,
        });
      });
    }
    if (_currentIndex < _steps.length) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPreviousPage() {
    if (_currentIndex > 0) {
      setState(() {
        // Clear the selection of the previous step so the user is forced to choose again
        _steps[_currentIndex - 1].selectedOption = null;

        // Also clear the current step just to ensure a clean slate if they move forward again
        if (_currentIndex < _steps.length) {
          _steps[_currentIndex].selectedOption = null;
        }
      });

      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _handleSelection(
    int stepIndex,
    String selectedValue,
    String selectedTitle,
  ) {
    setState(() {
      _steps[stepIndex].selectedOption = selectedValue;
      _steps[stepIndex].selectedOptionTitle = selectedTitle;
      // آپدیت کردن قیمت تکی و دوتایی
      if (stepIndex == 0) {
        for (var option in _steps[0].options) {
          if (option.serial == selectedValue) {
            _steps[1].options[0].priceDiff = option.priceDiff;
            _steps[1].options[1].priceDiff =
                (option.product!.companyShare *
                            option.product!.companyDoubleRate +
                        option.product!.parnterShare *
                            option.product!.partnerDoubleRate)
                    .floor();
          }
        }
      }
    });

    // Add a tiny delay so the user sees the button press highlight
    // before the page swipes to the next one.
    Future.delayed(const Duration(milliseconds: 200), () {
      _goToNextPage();
    });
  }

  void finalizeOrder() {
    List<Product> products = [];
    for (int i = 0; i < _steps.length; i++) {
      for (var option in _steps[i].options) {
        if (option.serial == _steps[i].selectedOption) {
          if (i == 0) {
            products.add(option.product!);
          } else if (i == 1) {
            products[0].quantity = (option.serial == "double") ? 2 : 1;
          } else {
            if (option.serial.indexOf("no__") != 0) {
              products.add(option.product!);
            }
          }
        }
      }
    }
    ref.read(selectedProductsProvider.notifier).setProducts(products);
  }

  // Resets the whole order flow (steps, selections and provider).
  // Only triggered when the selected products provider is explicitly
  // emptied (i.e. from the transaction success page button).
  void _resetOrder() {
    if (!mounted) {
      return;
    }
    setState(() {
      _currentIndex = 0;
      _finalPriceFuture = null;
      for (final step in _steps) {
        step.selectedOption = null;
        step.selectedOptionTitle = null;
      }
      _selectDefaultOption(0);
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    // Ensure the UI reflects the default selection even if the page
    // didn't change (jumpToPage(0) is a no-op when already on page 0).
    if (mounted) {
      setState(() {
        _selectDefaultOption(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // PopScope ensures system back buttons (Android/Web) trigger our custom back logic
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _goToPreviousPage();
        }
      },
      child: LoadingOverlay(
        show: _isLoadingProducts || _isStartingPayment,
        message: _isLoadingProducts
            ? 'در حال دریافت اطلاعات دستگاه...'
            : 'در حال دریافت تخفیف ها...',
        child: Scaffold(
          appBar: AppBar(
            title: Text("ثبت سفارش"),
            centerTitle: true,
            leading: _currentIndex > 0
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _goToPreviousPage,
                    tooltip: 'بازگشت',
                  )
                : null,
          ),
          body: PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                // First option of each step is selected by default
                _selectDefaultOption(index);
              });
            },
            // +1 to account for the final summary page
            itemCount: _steps.length + 1,
            itemBuilder: (context, index) {
              if (index == _steps.length) {
                return _buildSummaryPage();
              }
              return _buildChoicePage(index);
            },
          ),
          bottomNavigationBar: _buildBottomNavBar(),
        ),
      ),
    );
  }

  // Bottom navigation: left (previous option) - OK (confirm) - right (next option)
  Widget _buildBottomNavBar() {
    final colorScheme = Theme.of(context).colorScheme;
    // Shrink the nav buttons when the window height is too small
    final compact = MediaQuery.of(context).size.height < 600;
    final visualDensity = compact
        ? VisualDensity.compact
        : VisualDensity.standard;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24.0,
          vertical: compact ? 4.0 : 12.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Left button: back / reset to the first step
            IconButton.filledTonal(
              onPressed: _goBack,
              icon: const Icon(Icons.subdirectory_arrow_left, color: Colors.red),
              tooltip: 'بازگشت',
              visualDensity: visualDensity,
            ),
            const SizedBox(width: 16),

            // OK button: confirm selection / finalize order.
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

            // Right button: next option
            IconButton.filledTonal(
              onPressed: _selectNextOption,
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'گزینه بعدی',
              visualDensity: visualDensity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoicePage(int index) {
    final step = _steps[index];
    // Shrink the option buttons when the window height is too small
    final screenHeight = MediaQuery.of(context).size.height;
    final compact = screenHeight < 600;
    final buttonScale = compact ? 0.7 : 1.0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              step.question,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 18 : 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: compact ? 20 : 40),

            // ConstrainedBox handles ultra-wide screens (Tablets/Web)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              // All options are laid out in a single row
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: step.options.length.clamp(1, 100),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  // Wider aspect ratio so the row stays minimal in height
                  childAspectRatio: compact ? 2.2 : 1.6,
                ),
                itemCount: step.options.length,
                itemBuilder: (context, optionIndex) {
                  return _buildSquareButton(
                    stepIndex: index,
                    option: step.options[optionIndex],
                    priceDiff: step.options[optionIndex].priceDiff,
                    scale: buttonScale,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareButton({
    required int stepIndex,
    required ChoiceOption option,
    required int priceDiff,
    required double scale,
  }) {
    final step = _steps[stepIndex];
    final isSelected = step.selectedOption == option.serial;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: isSelected ? 8 : 2,
      color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: InkWell(
        onTap: () => _handleSelection(stepIndex, option.serial, option.title),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12.0 * scale,
            vertical: 8.0 * scale,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                option.icon,
                size: 32 * scale,
                color: isSelected ? colorScheme.primary : Colors.grey[700],
              ),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      option.title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? colorScheme.primary
                            : Colors.black87,
                      ),
                    ),
                    SizedBox(height: 4 * scale),
                    Text(
                      priceDiff >= 0
                          ? "${persianFormatter.format(priceDiff / 10)} تومان"
                          : "${persianFormatter.format(-priceDiff / 10)} تومان سود",
                      textAlign: TextAlign.center,
                      textDirection: .rtl,
                      style: TextStyle(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.bold,
                        color: priceDiff >= 0
                            ? Colors.black54
                            : Colors.green[300],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A final page to show the user what they selected
  Widget _buildSummaryPage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 80, color: Colors.teal),
              const SizedBox(height: 24),
              const Text(
                'تایید سفارش',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                // GridView dynamically handles any number of items and ensures they are squares
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent:
                        250, // Ensures items sit beside each other on mobile
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.5, // Forces perfect squares
                  ),
                  itemCount: _steps.length,
                  itemBuilder: (context, optionIndex) {
                    return Card(
                      elevation: 2,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                        side: BorderSide(color: Colors.transparent, width: 2.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _steps[optionIndex].title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _steps[optionIndex].selectedOptionTitle ?? "",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              FutureBuilder(
                future: _finalPriceFuture,
                builder: (context, snapshot) {
                  Widget result;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    result = const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    );
                  } else if (snapshot.hasData) {
                    final finalrawprice = snapshot.data;
                    result = Text(
                      'مبلغ نهایی: ${persianFormatter.format(finalrawprice! / 10)} تومان',
                      textDirection: .rtl,
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  } else {
                    result = SizedBox.shrink();
                  }
                  return result;
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                runAlignment: WrapAlignment.spaceEvenly,
                spacing: 20,
                runSpacing: 20,
                children: [
                  _buildPaymentButton(
                    index: 0,
                    label: 'پرداخت با اشتراک',
                    color: Colors.redAccent,
                    onPressed: () {},
                  ),
                  _buildPaymentButton(
                    index: 1,
                    label: 'پرداخت با شاتکارت',
                    color: Colors.deepOrange,
                    onPressed: () {
                      finalizeOrder();
                      context.push("/nfc_use");
                    },
                  ),
                  _buildPaymentButton(
                    index: 2,
                    label: 'پرداخت با تلفن همراه',
                    color: Colors.blueAccent,
                    onPressed: () {},
                  ),
                  _buildPaymentButton(
                    index: 3,
                    label: 'پرداخت با کارتخوان',
                    color: Colors.purple,
                    isLoading: _isStartingPayment,
                    onPressed: () {
                      _startCardPayment();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // A payment button on the summary page. Treated like an option: the
  // selected one is highlighted, and OK triggers its action.
  Widget _buildPaymentButton({
    required int index,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    bool isLoading = false,
  }) {
    final isSelected = _selectedSummaryOption == index;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 25),
        side: BorderSide(
          color: isSelected ? Colors.black : Colors.transparent,
          width: 3,
        ),
        elevation: isSelected ? 8 : 2,
      ),
      onPressed: isLoading
          ? null
          : () {
              setState(() {
                _selectedSummaryOption = index;
              });
              onPressed();
            },
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(color: Colors.white)),
    );
  }
}
