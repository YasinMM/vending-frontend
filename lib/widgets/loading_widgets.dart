import 'package:flutter/material.dart';

/// Full-screen modal loading overlay. Wrap the Scaffold body (or the whole
/// Scaffold) with this and toggle [show] while a network request is running.
/// Blocks all interaction while visible so the user cannot double-submit.
class LoadingOverlay extends StatelessWidget {
  final bool show;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.show,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (show)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            message!,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// An ElevatedButton that shows a spinner (and disables itself) while
/// [isLoading] is true. Use for buttons that trigger a Dio request.
class LoadingButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback? onPressed;
  final TextStyle? textStyle;

  const LoadingButton({
    super.key,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.onPressed,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        elevation: 2,
      ),
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(label, style: textStyle ?? const TextStyle(color: Colors.white)),
    );
  }
}
