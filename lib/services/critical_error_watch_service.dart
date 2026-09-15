import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Represents a critical error log fetched from the server.
class CriticalError {
  final int id;
  final DateTime creationDate;
  final String errorCode;
  final String userMessage;

  CriticalError({
    required this.id,
    required this.creationDate,
    required this.errorCode,
    required this.userMessage,
  });

  factory CriticalError.fromJson(Map<String, dynamic> json) {
    return CriticalError(
      id: json["id"],
      creationDate: DateTime.parse(json["creation_date"]),
      errorCode: json["error_code"],
      userMessage: json["user_message"],
    );
  }
}

/// Polls the server for critical error logs created for the active machine
/// and shows an alert dialog in the main window the moment one appears.
/// This service must be started only in the original (main) window — the
/// simulation page runs in a separate tab/window and doesn't poll.
class CriticalErrorWatchService {
  CriticalErrorWatchService._();

  static final CriticalErrorWatchService instance = CriticalErrorWatchService._();

  static const Duration _pollInterval = Duration(seconds: 5);

  Timer? _timer;
  DateTime? _lastCheck;
  bool _isChecking = false;
  final persianFormatter = NumberFormat.decimalPattern('fa');

  /// Starts polling. Safe to call multiple times.
  void start(WidgetRef ref, GoRouter router) {
    _timer?.cancel();
    _lastCheck = DateTime.now().toUtc();
    _timer = Timer.periodic(_pollInterval, (_) async {
      await _check(ref, router);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check(WidgetRef ref, GoRouter router) async {
    if (_isChecking) {
      return;
    }
    _isChecking = true;
    try {
      final machineSerial = ref.read(activeMachineProvider);
      final sinceIso = _lastCheck?.toIso8601String();
      _lastCheck = DateTime.now().toUtc();
      final response = await ProductService.getCriticalErrorLogs(
        machineSerial,
        sinceIso: sinceIso,
      );
      if (response.data is List && (response.data as List).isNotEmpty) {
        final error = CriticalError.fromJson(
          Map<String, dynamic>.from((response.data as List).first),
        );
        _showAlertDialog(router, error);
      }
    } on DioException {
      // Network errors are ignored; the next poll will retry.
    } finally {
      _isChecking = false;
    }
  }

  void _showAlertDialog(GoRouter router, CriticalError error) {
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    // The timer can fire while the tree is mid-layout (e.g. right after a
    // jumpToPage / inactivity reset), when the Overlay's RenderBox hasn't
    // been laid out yet. Showing a dialog then crashes with
    // "RenderBox was not laid out: _RenderTheater". Deferring to a
    // post-frame callback guarantees the frame is complete and laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Directionality(
            textDirection: .rtl,
            child: AlertDialog(
              icon: const Icon(
                Icons.error,
                size: 64,
                color: Colors.red,
              ),
              title: const Text('خطای بحرانی!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error.userMessage),
                  const SizedBox(height: 12),
                  Text(
                    'کد خطا: ${error.errorCode}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'لطفاً با صاحب دستگاه تماس بگیرید.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('باشه'),
                ),
              ],
            ),
          ),
        );
      },
      );
    });
  }
}
