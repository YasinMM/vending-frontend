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
  final int? sensorId;

  CriticalError({
    required this.id,
    required this.creationDate,
    required this.errorCode,
    required this.userMessage,
    required this.sensorId,
  });

  factory CriticalError.fromJson(Map<String, dynamic> json) {
    return CriticalError(
      id: json["id"],
      creationDate: DateTime.parse(json["creation_date"]),
      errorCode: json["error_code"],
      userMessage: json["user_message"],
      sensorId: json["sensor_id"] as int?,
    );
  }
}

/// Polls the server for critical error logs created for the active machine
/// and shows an alert dialog in the main window the moment one appears.
/// This service must be started only in the original (main) window — the
/// simulation page runs in a separate tab/window and doesn't poll.
class CriticalErrorWatchService {
  CriticalErrorWatchService._();

  static final CriticalErrorWatchService instance =
      CriticalErrorWatchService._();

  static const Duration _pollInterval = Duration(seconds: 5);

  Timer? _timer;
  DateTime? _lastCheck;
  bool _isChecking = false;
  String? _activeMachineSerial;
  final Set<int> _watchedErrorIds = {};
  final Set<int> _shownErrorIds = {};
  final Map<int, BuildContext> _dialogContexts = {};
  final persianFormatter = NumberFormat.decimalPattern('fa');

  /// Starts polling. Safe to call multiple times.
  void start(WidgetRef ref, GoRouter router) {
    _timer?.cancel();
    _activeMachineSerial = ref.read(activeMachineProvider);
    _watchedErrorIds.clear();
    _shownErrorIds.clear();
    _dialogContexts.clear();
    _lastCheck = DateTime.now().toUtc();
    _timer = Timer.periodic(_pollInterval, (_) async {
      await _check(ref, router);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _watchedErrorIds.clear();
    _shownErrorIds.clear();
    _dialogContexts.clear();
  }

  Future<void> _check(WidgetRef ref, GoRouter router) async {
    if (_isChecking) {
      return;
    }
    _isChecking = true;
    try {
      final machineSerial = ref.read(activeMachineProvider);
      if (_activeMachineSerial != machineSerial) {
        _activeMachineSerial = machineSerial;
        _watchedErrorIds.clear();
        _shownErrorIds.clear();
        _dialogContexts.clear();
        _lastCheck = DateTime.now().toUtc();
      }
      final sinceIso = _lastCheck?.toIso8601String();
      _lastCheck = DateTime.now().toUtc();
      final response = await ProductService.getCriticalErrorLogs(
        machineSerial,
        sinceIso: sinceIso,
        watchedIds: _watchedErrorIds.toList(),
      );
      if (response.data is List && (response.data as List).isNotEmpty) {
        for (final item in response.data as List) {
          final json = Map<String, dynamic>.from(item);
          final id = json['id'] as int;
          if (json['active'] != true) {
            _watchedErrorIds.remove(id);
            if (_shownErrorIds.remove(id)) {
              _dismissErrorDialog(id);
            }
            continue;
          }
          if (json['sensor_id'] != null) _watchedErrorIds.add(id);
          if (json['newly_created'] == true && _shownErrorIds.add(id)) {
            _showAlertDialog(router, CriticalError.fromJson(json));
          }
        }
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
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _dialogContexts[error.id] = dialogContext;
          return PopScope(
            canPop: false,
            child: Directionality(
              textDirection: .rtl,
              child: AlertDialog(
                icon: const Icon(Icons.error, size: 64, color: Colors.red),
                title: const Text('خطای بحرانی!'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      error.userMessage,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'کد خطا: ${error.errorCode}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    });
  }

  void _dismissErrorDialog(int errorId) {
    final dialogContext = _dialogContexts.remove(errorId);
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop();
    }
  }
}
