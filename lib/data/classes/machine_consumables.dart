/// Availability rules for product options based on the machine's consumables.
///
/// The backend returns, for a given machine:
///  - `consumables`: the current amount of every consumable, already
///    recalculated from the consumable-change records.
///  - `products`: for each product, how much of each consumable a single unit
///    (`single`) and a double serving (`double`) requires.
///
/// An option is sellable when the machine holds at least the required amount
/// of every consumable that product needs.
class MachineConsumables {
  /// Current amount per consumable serial.
  final Map<String, double> amounts;

  /// Required amount per product serial, keyed by consumable serial.
  /// The inner "quantity" key is "single" or "double".
  final Map<String, Map<String, Map<String, double>>> requirements;

  /// Whether a server response has been received at least once. Before that,
  /// [canDispense] must not treat the (still unknown) stock as empty,
  /// otherwise every option would flash as disabled on startup.
  final bool loaded;

  const MachineConsumables({
    this.amounts = const {},
    this.requirements = const {},
    this.loaded = false,
  });

  /// Placeholder used before the first response arrives.
  static const MachineConsumables empty = MachineConsumables();

  /// Parses the `/getmachineconsumablelist` payload.
  factory MachineConsumables.fromJson(Map<String, dynamic> data) {
    final amounts = <String, double>{};
    final rawConsumables = data['consumables'];
    if (rawConsumables is List) {
      for (final entry in rawConsumables) {
        if (entry is Map && entry['serial'] != null) {
          amounts[entry['serial'].toString()] =
              _toDouble(entry['amount']);
        }
      }
    }

    final requirements = <String, Map<String, Map<String, double>>>{};
    final rawProducts = data['products'];
    if (rawProducts is List) {
      for (final entry in rawProducts) {
        if (entry is! Map || entry['product_serial'] == null) {
          continue;
        }
        final productSerial = entry['product_serial'].toString();
        requirements[productSerial] = {
          'single': _readRequirements(entry['single']),
          'double': _readRequirements(entry['double']),
        };
      }
    }

    return MachineConsumables(
      amounts: amounts,
      requirements: requirements,
      loaded: true,
    );
  }

  static double _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, double> _readRequirements(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    return {
      for (final entry in raw.entries)
        entry.key.toString(): _toDouble(entry.value),
    };
  }

  /// Whether [productSerial] can be dispensed in [quantity] units
  /// (1 = single, 2 = double) given the machine's current amounts.
  ///
  /// A product with no consumable requirements is always available. A
  /// consumable the machine has no row for is treated as unavailable, because
  /// the amount cannot be proven to be sufficient.
  ///
  /// Before the first response arrives nothing is known yet, so every product
  /// is reported as available and the UI simply waits for [loaded].
  bool canDispense(String productSerial, int quantity) {
    if (!loaded) {
      return true;
    }
    final key = quantity == 2 ? 'double' : 'single';
    final needed = requirements[productSerial]?[key];
    if (needed == null || needed.isEmpty) {
      return true;
    }
    for (final entry in needed.entries) {
      final available = amounts[entry.key];
      if (available == null || available < entry.value) {
        return false;
      }
    }
    return true;
  }

  /// Whether the machine holds less than a *single* serving of
  /// [productSerial]. This is the condition that makes the product itself
  /// (the main drink option) undispensable; the "double" size has its own,
  /// separate check.
  bool isBelowSingleAmount(String productSerial) {
    if (!loaded) {
      return false;
    }
    return !canDispense(productSerial, 1);
  }
}
