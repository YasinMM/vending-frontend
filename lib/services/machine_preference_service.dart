import 'package:shared_preferences/shared_preferences.dart';

/// Persists the machine the user last selected on the product page.
///
/// The value is kept in an in-memory cache ([cached]) that is hydrated once
/// during startup, before the first frame. That lets
/// `activeMachineProvider` stay a plain synchronous `String` provider while
/// still restoring the previous choice on a fresh browser load.
class MachinePreferenceService {
  MachinePreferenceService._();

  static const String _storageKey = 'selected_machine_serial';

  static String? _cached;

  /// The last selected machine serial, or `null` if nothing was stored yet.
  static String? get cached => _cached;

  /// Reads the stored machine into the in-memory cache. Safe to call more
  /// than once; the last call wins.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cached = prefs.getString(_storageKey);
    } catch (_) {
      // Storage unavailable (e.g. private browsing / disabled cookies):
      // keep the default machine instead of failing app startup.
      _cached = null;
    }
  }

  /// Stores [serial] as the selected machine and updates the in-memory cache.
  static Future<void> save(String serial) async {
    _cached = serial;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, serial);
    } catch (_) {
      // Non-fatal: the choice still applies for the current session.
    }
  }
}
