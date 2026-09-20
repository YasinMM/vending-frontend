import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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

  Future<List<_OnlineDiscount>> _fetchPinnedDiscounts(String serial) async {
    final response = await ProductService.getMachinePinnedDiscountList(serial);
    final List<_OnlineDiscount> discounts = [];
    if (response.data.length != 0) {
      for (Map<String, dynamic> d in response.data) {
        var machineSerials = List<String>.from(d["machine_serials"]);
        discounts.add(
          _OnlineDiscount(
            code: d["code"],
            name: d["name"],
            description: d["description"],
            pinned: (machineSerials.contains(serial))
                ? d["is_pinned"][machineSerials.indexOf(serial)]
                : false,
          ),
        );
      }
    }
    return discounts;
  }

  Future<List<_OnlineDiscount>> _fetchUserDiscounts(
    String serial,
    int user,
  ) async {
    final response = await ProductService.getUserMachineDiscountList(
      serial,
      user,
    );
    final List<_OnlineDiscount> discounts = [];
    if (response.data.length != 0) {
      for (Map<String, dynamic> d in response.data) {
        var machineSerials = List<String>.from(d["machine_serials"]);
        discounts.add(
          _OnlineDiscount(
            code: d["code"],
            name: d["name"],
            description: d["description"],
            pinned: (machineSerials.contains(serial))
                ? d["is_pinned"][machineSerials.indexOf(serial)]
                : false,
          ),
        );
      }
    }
    return discounts;
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
        "discount_codes": _allDiscounts
            .where((d) => d.selected)
            .map((d) => d.code)
            .toList(),
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

  List<String> get _selectedDiscountCodes => _allDiscounts
      .where((d) => d.selected)
      .map((d) => d.code)
      .toList();

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

  // Acts the same as the "pay with wallet" button on the discount page:
  // creates a wallet purchase transaction with the selected discounts.
  Future<void> _payWithWallet() async {
    final payload = _readPayload();
    if (payload == null || _user == -1) {
      return;
    }
    setState(() {
      _isPaying = true;
    });
    try {
      await ProductService.createUserWalletPurchase({
        "creation_date": DateTime.now().toIso8601String(),
        "discount_codes": _selectedDiscountCodes,
        "user": _user,
        "machine_serial": payload["machine_serial"],
        "amount": _finalPrice,
        "product_serials": payload["product_serials"],
        "quantities": payload["quantities"],
      });
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
                final isSelected = discount.selected;

                return Directionality(
                  textDirection: .rtl,
                  child: Card(
                    elevation: isSelected ? 4 : 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          discount.selected = !discount.selected;
                        });
                        _updateFinalPrice();
                      },
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
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black87,
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
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
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
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
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
              // Pay with wallet: only when logged in and balance is known.
              if (_user != -1)
                Column(
                  children: [
                    ElevatedButton(
                      onPressed:
                          (_isPaying ||
                              _walletBalance == null ||
                              _finalPrice == null ||
                              _walletBalance! <= 0)
                          ? null
                          : _payWithWallet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        _walletBalance != null &&
                                _finalPrice != null &&
                                _walletBalance! > 0 &&
                                _walletBalance! < _finalPrice!
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
  bool selected;

  _OnlineDiscount({
    required this.code,
    required this.name,
    required this.pinned,
    this.description,
    this.selected = false,
  });
}
