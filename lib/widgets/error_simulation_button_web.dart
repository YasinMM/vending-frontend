// Web implementation: opens the given app route in a new browser tab.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void openInNewBrowserTab(String path) {
  final origin = html.window.location.origin;
  final base = html.window.location.pathname?.replaceFirst(RegExp(r'index\.html$'), '') ?? '/';
  html.window.open('$origin$base#$path', '_blank');
}
