import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

// Platform-specific URL launcher: on web we open a new browser tab,
// on other platforms we fall back to in-app navigation.
// The two stub/impl libraries are swapped at compile time.
import 'error_simulation_button_stub.dart'
    if (dart.library.html) 'error_simulation_button_web.dart';
export 'error_simulation_button_stub.dart'
    if (dart.library.html) 'error_simulation_button_web.dart';

/// A small button fixed to the corner of every page. Clicking it opens the
/// error simulation page in a new window/tab so the kiosk flow is not disturbed.
class ErrorSimulationButton extends StatelessWidget {
  const ErrorSimulationButton({super.key});

  static const String routePath = '/error_simulation';

  static void openNewTab(BuildContext context) {
    // On web, window.open triggers an immediate view-focus change on the
    // current window. If it happens during the tap event (before the frame
    // scheduled by this tap is built/laid out), the focus manager's traversal
    // reads the Overlay's bounds while it is still NEEDS-LAYOUT and crashes
    // with "RenderBox was not laid out: _RenderTheater". Deferring to a
    // post-frame callback lets the frame finish first.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      openInNewBrowserTab(routePath);
    });
    // Fallback for non-web platforms (no real "new window" concept):
    if (!kIsWeb) {
      context.push(routePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          // Note: no Tooltip here — this button lives outside the app's
          // Navigator/Overlay (in MaterialApp.builder), so tooltips cannot
          // find an Overlay ancestor and would crash.
          child: IconButton.filledTonal(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            onPressed: () => openNewTab(context),
            icon: const Icon(Icons.bug_report, size: 18),
          ),
        ),
      ),
    );
  }
}
