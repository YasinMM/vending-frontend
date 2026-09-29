import 'dart:async';

import 'package:flutter/material.dart';

/// Displays a temporary notification in the top-right corner of the app.
class CornerNotification {
  CornerNotification._();

  static OverlayEntry? _entry;
  static Timer? _dismissTimer;

  /// Shows [message] for [duration], replacing any notification already shown.
  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 4),
  }) {
    _dismissTimer?.cancel();
    _entry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final colorScheme = Theme.of(overlayContext).colorScheme;
        return Positioned(
          top: MediaQuery.paddingOf(overlayContext).top + 16,
          right: 16,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(12 * (1 - value), 0),
                    child: child,
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(overlayContext).width - 32,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.inverseSurface,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline, color: colorScheme.onInverseSurface),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              message,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(color: colorScheme.onInverseSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _entry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (_entry == entry) {
        entry.remove();
        _entry = null;
        _dismissTimer = null;
      }
    });
  }
}