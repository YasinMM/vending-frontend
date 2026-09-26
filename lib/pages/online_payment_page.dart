import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/data/classes/discount_json.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/loading_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
class OnlinePaymentPage extends StatefulWidget {
  const OnlinePaymentPage({super.key});

  @override
  State<OnlinePaymentPage> createState() => _OnlinePaymentPageState();
}

class _OnlinePaymentPageState extends State<OnlinePaymentPage>
    with SingleTickerProviderStateMixin {
  final persianFormatter = NumberFormat.decimalPattern('fa');
  bool _isPaying = false;
  bool _isLoadingDiscounts = false;
  bool _isLoadingPrice = false;
  bool _isLoadingWallet = false;

  // Final price calculated on the backend based on the selected discounts
  int? _finalPrice;

  // Wallet balance of the logged-in user
  int? _walletBalance;

  // Pinned discounts fetched when the user clicks "pay online" — shown
  // for selection before the payment, like the card payment flow.
  List<_OnlineDiscount> _pinnedDiscounts = [];

  // Discounts of the logged-in user (fetched when a user button is pressed)
  List<_OnlineDiscount> _userDiscounts = [];

  // Login page (user selection) vs discounts selection view
  bool _showDiscountSelection = false;

  // Currently logged-in user (-1 = guest)
  int _user = -1;

  // Animated icon on the login page (like the NFC use page)
  AnimationController? _controller;
  Animation<double>? _scaleAnimation;

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
      CurvedAnimation(parent: _controller!, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _readPayload() {
    // The order data is handed over through the URL query string
    // (base64-encoded JSON), so the page works in any browser.
    final query = Uri.base.queryParameters['data'] ??
        Uri.base.fragment.split('?').last.split('data=').last;
    if (query.isEmpty) {
      return null;
    }
    try {
      final decoded = utf8.decode(base64Url.decode(query));
      return Map<String, dynamic>.from(jsonDecode(decoded) as Map);
    } catch (_) {
      return null;
    }
  }

  // Payment completed: show the transaction success page in this window.
  void _finishPayment() {
    if (mounted) {
      context.go("/transaction_success");
    }
  }

  // Fetches the discounts of the selected user merged with the pinned
  // discounts of the machine — the same as the card flow (the NFC use
  // page fetches the user's discounts, then the discounts page also
  // shows the machine's pinned ones).
  Future<void> _selectUser(int user) async {
    setState(() {
      _isLoadingDiscounts = true;
      _user = user;
    });
    try {
      final payload = _readPayload();
      final serial = payload?['machine_serial'] as String? ?? '';

      // 1. Pinned discounts of the machine — always fetched fresh.
      final List<_OnlineDiscount> pinned =
          await _fetchPinnedDiscounts(serial);

      if (!mounted) {
        return;
      }
      setState(() {
        _pinnedDiscounts = pinned;
        _userDiscounts = [];
        _showDiscountSelection = true;
      });
      await _updateFinalPrice();

      // 2. The user's own discounts (guests have none). Kept separate so
      // a failure here doesn't hide the already-shown pinned discounts.
      if (user != -1) {
        try {
          final userDiscounts = await _fetchUserDiscounts(serial, user);
          if (!mounted) {
            return;
          }
          setState(() {
            _userDiscounts = userDiscounts;
          });
          await _updateFinalPrice();
        } on DioException {
          // User discounts unavailable: continue with pinned only.
        }
      }

      if (mounted) {
        await _loadWalletBalance();
      }
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingDiscounts = false;
        _showDiscountSelection = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingDiscounts = false;
        });
      }
    }
  }

  // Maps one discount entry of the backend to the local model.
  _OnlineDiscount _toOnlineDiscount(Map<String, dynamic> d, String serial) {
    return _OnlineDiscount(
      code: d["code"],
      name: d["name"],
      description: d["description"],
      productLimit: readProductLimit(d),
      productSerials: readProductSerials(d),
      // Resolved defensively: the backend builds "machine_serials" and
      // "is_pinned" with two independent queries, so indexing the second by
      // the first one's position can go out of range.
      pinned: readPinnedForMachine(d, serial),
    );
  }

  Future<List<_OnlineDiscount>> _fetchPinnedDiscounts(String serial) async {
    final response = await ProductService.getMachinePinnedDiscountList(serial);
    if (response.data.length == 0) {
      return [];
    }
    return (response.data as List)
        .map((d) => _toOnlineDiscount(Map<String, dynamic>.from(d), serial))
        .toList();
  }

  Future<List<_OnlineDiscount>> _fetchUserDiscounts(
    String serial,
    int user,
  ) async {
    final response = await ProductService.getUserMachineDiscountList(
      serial,
      user,
    );
    if (response.data.length == 0) {
      return [];
    }
    return (response.data as List)
        .map((d) => _toOnlineDiscount(Map<String, dynamic>.from(d), serial))
        .toList();
  }

  Future<void> _loadWalletBalance() async {
    if (_user == -1) {
      return;
    }
    setState(() {
      _isLoadingWallet = true;
    });
    try {
      final response = await ProductService.getWalletByUser(_user);
      final data = response.data;
      final balance = data is Map ? data['balance'] : data;
      if (!mounted) {
        return;
      }
      setState(() {
        _walletBalance = balance is num ? balance.toInt() : null;
        _isLoadingWallet = false;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _walletBalance = null;
        _isLoadingWallet = false;
      });
    }
  }

  // All discounts available for selection (user's + machine's pinned ones,
  // deduplicated by code).
  List<_OnlineDiscount> get _allDiscounts {
    final Map<String, _OnlineDiscount> byCode = {};
    for (final d in [..._userDiscounts, ..._pinnedDiscounts]) {
      byCode[d.code] = d;
    }
    return byCode.values.toList();
  }

  // The products the customer picked in the main tab, taken from the payload.
  Set<String> get _payloadProductSerials {
    final payload = _readPayload();
    final raw = payload?['product_serials'];
    if (raw is! List) {
      return <String>{};
    }
    return raw.map((e) => e.toString()).toSet();
  }

  // Same rule as the discount page: a product-limited discount is only usable
  // when at least one of the ordered products is part of its product list.
  bool _isDiscountAvailable(_OnlineDiscount discount) {
    if (!discount.productLimit || discount.productSerials.isEmpty) {
      return true;
    }
    return _payloadProductSerials.any(discount.productSerials.contains);
  }

  // A discount can only be selected while it is available (the price request
  // is skipped for unavailable ones), and it is silently dropped if it turned
  // out to be unavailable in the meantime.
  List<String> get _selectedDiscountCodes => _allDiscounts
      .where((d) => d.selected && _isDiscountAvailable(d))
      .map((d) => d.code)
      .toList();

  // The wallet button is only usable when the balance is known and above zero.
  // A zero or unknown balance keeps it disabled, since there would be nothing
  // to charge the purchase against.
  bool get _isWalletButtonEnabled =>
      !_isPaying &&
      !_isLoadingWallet &&
      _walletBalance != null &&
      _walletBalance! > 0 &&
      _finalPrice != null &&
      _finalPrice! > 0;

  // Between a positive balance and the final price: the wallet is topped up
  // with the missing amount ("افزایش اعتبار") instead of paying directly.
  bool get _needsWalletTopUp =>
      _walletBalance != null &&
      _finalPrice != null &&
      _walletBalance! < _finalPrice!;

  // Calculates the final price from the backend based on the currently
  // selected discounts (same request the card flow / discount page use).
  Future<void> _updateFinalPrice() async {
    final payload = _readPayload();
    if (payload == null) {
      return;
    }
    setState(() {
      _isLoadingPrice = true;
    });
    try {
      final response = await ProductService.getFinalPriceFromList({
        "discount_codes": _selectedDiscountCodes,
        "machine_serial": payload["machine_serial"],
        "product_serials": payload["product_serials"],
        "quantities": payload["quantities"],
      });
      if (!mounted) {
        return;
      }
      setState(() {
        _finalPrice = response.data.length != 0
            ? response.data["data"]
            : -1;
        _isLoadingPrice = false;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _finalPrice = -1;
        _isLoadingPrice = false;
      });
    }
  }

  // Acts the same as the "pay with card" button on the summary page:
  // first calculates the final price (the backend requires the "amount"
  // field, which the card flow also computes before posting), then
  // creates the card purchase transaction (user variant when logged in).
  Future<void> _payOnline() async {
    final payload = _readPayload();
    if (payload == null) {
      return;
    }
    payload["discount_codes"] = _selectedDiscountCodes;

    setState(() {
      _isPaying = true;
    });
    try {
      final priceResponse = await ProductService.getFinalPriceFromList({
        "discount_codes": payload["discount_codes"],
        "machine_serial": payload["machine_serial"],
        "product_serials": payload["product_serials"],
        "quantities": payload["quantities"],
      });
      payload["amount"] = priceResponse.data["data"];
      if (_user == -1) {
        payload.remove("user");
        await ProductService.createCardPurchaseTransaction(payload);
      } else {
        // The payload was built in the main tab where the user was still
        // a guest (-1) — override it with the user chosen in this tab.
        payload["user"] = _user;
        await ProductService.createUserCardPurchaseTransaction(payload);
      }
      _finishPayment();
    } on DioException {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
    }
  }

  // Builds the wallet purchase body, exactly like the card-swipe page does in
  // "increase wallet balance" mode, so both flows post the same transaction.
  Map<String, dynamic> _buildWalletPurchaseData(int amount) {
    final payload = _readPayload();
    return {
      "creation_date": DateTime.now().toIso8601String(),
      "discount_codes": _selectedDiscountCodes,
      "user": _user,
      "machine_serial": payload?["machine_serial"],
      "amount": amount,
      "product_serials": payload?["product_serials"],
      "quantities": payload?["quantities"],
    };
  }

  // Acts the same as the "pay with wallet" button on the discount page, or as
  // the "کردم" (OK) button on the card swipe page in "increase wallet balance"
  // mode: when the balance doesn't cover the price, the missing amount is
  // deposited first and then the whole purchase is charged to the wallet —
  // exactly like the card swipe deposit flow.
  Future<void> _payWithWallet() async {
    final payload = _readPayload();
    if (payload == null || _user == -1 || _finalPrice == null ||
        _finalPrice! <= 0) {
      return;
    }
    setState(() {
      _isPaying = true;
    });
    try {
      final depositAmount = _finalPrice! - (_walletBalance ?? 0);
      if (depositAmount > 0) {
        // Top up the wallet with the missing amount first, same as the
        // card swipe "افزایش اعتبار" mode.
        await ProductService.depositToWallet({
          "creation_date": DateTime.now().toIso8601String(),
          "user": _user,
          "bank_serial": "123456",
          "amount": depositAmount,
        });
      }
      await ProductService.createUserWalletPurchase(
        _buildWalletPurchaseData(_finalPrice!),
      );
      _finishPayment();
    } on DioException {
      if (mounted) {
        setState(() {
          _isPaying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      show: _isLoadingDiscounts || _isPaying,
      message: _isPaying ? 'در حال ثبت تراکنش...' : 'در حال دریافت اطلاعات کاربر...',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پرداخت آنلاین'),
          centerTitle: true,
        ),
        body: Center(
          child: _showDiscountSelection
              ? _buildDiscountSelection()
              : _buildLoginPage(),
        ),

      ),
    );
  }

  // Login page: same layout as the NFC use page with three user buttons.
  Widget _buildLoginPage() {
    final isLoading = _isLoadingDiscounts;
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Looping animated icon
          if (_scaleAnimation != null)
            ScaleTransition(
              scale: _scaleAnimation!,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.language,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 48),

          // Instruction text
          Text(
            "برای استفاده از تخفیف‌ها وارد شوید.",
            textAlign: TextAlign.center,
            textDirection: .rtl,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 36),

          ElevatedButton(
            onPressed: isLoading ? null : () => _selectUser(1),
            child: isLoading
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
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isLoading ? null : () => _selectUser(2),
            child: isLoading
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
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isLoading ? null : () => _selectUser(3),
            child: isLoading
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
          ElevatedButton(
            onPressed: isLoading
                ? null
                : () async {
                    // Continue without logging in (guest): pinned only.
                    await _selectUser(-1);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('پرداخت آنلاین'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountSelection() {
    return Padding(
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
            child: _allDiscounts.isEmpty
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
              itemCount: _allDiscounts.length,
              itemBuilder: (context, index) {
                final discount = _allDiscounts[index];
                final isAvailable = _isDiscountAvailable(discount);
                final isSelected = isAvailable && discount.selected;

                return Directionality(
                  textDirection: .rtl,
                  // Unavailable (product-limited) discounts are dimmed and
                  // greyed out so it is obvious they can't be picked.
                  child: Opacity(
                    opacity: isAvailable ? 1.0 : 0.55,
                    child: Card(
                      elevation: isSelected ? 4 : 1,
                      color: isAvailable ? null : Colors.grey[200],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        side: BorderSide(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : isAvailable
                              ? Colors.transparent
                              : Colors.grey.shade400,
                          width: 2,
                        ),
                      ),
                      child: InkWell(
                        onTap: isAvailable
                            ? () {
                                setState(() {
                                  discount.selected = !discount.selected;
                                });
                                _updateFinalPrice();
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
                                  child: Text(
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
          Text(
            _isLoadingPrice
                ? 'قیمت نهایی: در حال محاسبه...'
                : _finalPrice == null
                ? 'قیمت نهایی: --'
                : _finalPrice == 0
                ? 'قیمت نهایی: رایگان'
                : _finalPrice == -1
                ? 'قیمت نهایی: --'
                : 'قیمت نهایی: ${persianFormatter.format(_finalPrice! / 10)} تومان',
            textDirection: .rtl,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              // Pay online: same as the card payment flow.
              ElevatedButton(
                onPressed: _isPaying ? null : _payOnline,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                child: _isPaying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('پرداخت آنلاین'),
              ),
              // Pay with wallet: only when logged in and the balance is
              // above zero. A balance that is too low to cover the price
              // turns this into the "افزایش اعتبار" (top up) action.
              if (_user != -1)
                Column(
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isWalletButtonEnabled ? _payWithWallet : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _needsWalletTopUp
                            ? 'افزایش اعتبار'
                            : 'پرداخت با کیف پول',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLoadingWallet
                          ? 'موجودی: در حال دریافت...'
                          : _walletBalance == null
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
          ),
        ],
      ),
    );
  }

}

// Lightweight discount model for the online payment tab. The full app
// state (riverpod providers) is fresh in a new window, so the discount
// selection here is local to this tab.
class _OnlineDiscount {
  final String code;
  final String name;
  final String? description;
  final bool pinned;

  // When productLimit is set, the discount only applies to the listed
  // products and is therefore unusable for any other order.
  final bool productLimit;
  final List<String> productSerials;

  // Toggled locally when the user picks/deselects the card.
  bool selected = false;

  _OnlineDiscount({
    required this.code,
    required this.name,
    required this.pinned,
    this.description,
    this.productLimit = false,
    this.productSerials = const <String>[],
  });
}
