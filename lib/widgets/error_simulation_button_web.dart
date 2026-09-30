// Web implementation: opens the given app route in a new browser tab.
import 'package:web/web.dart' as web;

void openInNewBrowserTab(String path) {
  final origin = web.window.location.origin;
  final base = web.window.location.pathname.replaceFirst(RegExp(r'index\.html$'), '');
  web.window.open('$origin$base#$path', '_blank');
}
