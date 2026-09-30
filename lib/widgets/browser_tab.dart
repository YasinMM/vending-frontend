// Platform-specific "open a new tab" helper: on the web we open a real browser
// tab, on other platforms it is a no-op. The two stub/impl libraries are
// swapped at compile time, so `dart:html` never leaks into other builds.
export 'browser_tab_stub.dart'
    if (dart.library.html) 'browser_tab_web.dart';