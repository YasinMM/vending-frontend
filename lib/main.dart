import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/pages/card_swipe_page.dart';
import 'package:flutter_production_test/pages/transaction_success_page.dart';
import 'package:flutter_production_test/pages/discount_page.dart';
import 'package:flutter_production_test/pages/nfc_use_page.dart';
import 'package:flutter_production_test/pages/product_page.dart';
import 'package:flutter_production_test/services/inactivity_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() {
  runApp(ProviderScope(child: MainApp()));
}


// تعریف صفحه ها
final routeObserver = RouteObserver<ModalRoute<void>>();

final _router = GoRouter(
  observers: [routeObserver],
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ProductPage(),
    ),
    GoRoute(
      path: '/discounts',
      builder: (context, state) => const DiscountPage(),
    ),
    GoRoute(
      path: '/card_swipe',
      builder: (context, state) {
        final extra = state.extra;
        final depositAmount = extra is Map<String, dynamic>
            ? extra['depositAmount'] as int?
            : null;
        final purchaseAmount = extra is Map<String, dynamic>
            ? extra['purchaseAmount'] as int?
            : null;

        return CardSwipePage(
          depositAmount: depositAmount,
          purchaseAmount: purchaseAmount,
        );
      },
    ),
    GoRoute(
      path: '/nfc_use',
      builder: (context, state) => const NfcUsePage(),
    ),
    GoRoute(
      path: '/transaction_success',
      builder: (context, state) => const TransactionSuccessPage(),
    ),
  ],
);

class DioClient {
  DioClient._();

  static final Dio dio = Dio(
    BaseOptions(
      baseUrl: "https://vending-backend-slfs.onrender.com",
      contentType: "application/json",
      
    ),
  ); 
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  @override
  void initState() {
    super.initState();
    // Configure the global inactivity timer (1 minute after the last
    // interaction the app resets to its default state).
    InactivityService.instance.configure(ref, _router);
    InactivityService.instance.reset();
  }

  @override
  Widget build(BuildContext context) {
    // Every pointer interaction (tap, click, etc.) resets the inactivity timer
    return Listener(
      onPointerDown: (_) => InactivityService.instance.reset(),
      onPointerMove: (_) => InactivityService.instance.reset(),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Shot Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),),
            routerConfig: _router,
      ),
    );
  }
}
