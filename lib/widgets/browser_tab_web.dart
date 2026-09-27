// Web implementation: opens the given absolute URL in a new browser tab.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Opens [url] in a new browser tab. The URL is expected to be absolute and
/// already contain the app's hash route.
void openInNewBrowserTabUrl(String url) {
  html.window.open(url, '_blank');
}
