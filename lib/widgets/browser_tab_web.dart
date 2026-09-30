// Web implementation: opens the given absolute URL in a new browser tab.
import 'package:web/web.dart' as web;

/// Opens [url] in a new browser tab. The URL is expected to be absolute and
/// already contain the app's hash route.
void openInNewBrowserTabUrl(String url) {
  web.window.open(url, '_blank');
}
