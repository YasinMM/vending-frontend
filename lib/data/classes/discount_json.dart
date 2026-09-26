/// Helpers for reading the discount payloads returned by the backend.
///
/// Both discount endpoints (`getmachinepinneddiscountlist` and
/// `getusermachinediscountlist`) attach three extra keys to every discount:
///
/// ```python
/// item["machine_serials"] = list(discount.machine_discounts.values_list("machine__serial", flat=True).distinct())
/// item["is_pinned"]       = list(discount.machine_discounts.values_list("is_pinned", flat=True).distinct())
/// ```
///
/// Those are two *independent* queries, so there is no guarantee the two
/// lists have the same length or the same ordering. Indexing `is_pinned` with
/// `machine_serials.indexOf(serial)` therefore throws a `RangeError` whenever
/// the two lists disagree (for example a discount linked to several machines
/// where one of the `is_pinned` rows is a duplicate of another).
///
/// [readPinnedForMachine] resolves the flag defensively so a mismatched
/// payload can never crash the page.
library;

/// Whether [discount] is pinned on the machine identified by [serial].
///
/// Returns `false` when the serial is not linked to the discount, when the
/// `is_pinned` list is missing or shorter than the index, or when the value
/// at that index is not a boolean.
bool readPinnedForMachine(Map<String, dynamic> discount, String serial) {
  final serials = discount["machine_serials"];
  if (serials is! List) {
    return false;
  }
  final index = serials.indexWhere((e) => e?.toString() == serial);
  if (index < 0) {
    return false;
  }

  final isPinned = discount["is_pinned"];
  if (isPinned is! List || index >= isPinned.length) {
    return false;
  }
  return isPinned[index] == true;
}

/// Reads the product serials a discount is restricted to.
///
/// Tolerates a missing or `null` value and non-string entries, returning an
/// empty list when the discount is not product limited.
List<String> readProductSerials(Map<String, dynamic> discount) {
  final raw = discount["product_serials"];
  if (raw is! List) {
    return <String>[];
  }
  return raw
      .where((e) => e != null)
      .map((e) => e.toString())
      .toList();
}

/// Reads the `product_limit` flag, defaulting to `false` when absent.
bool readProductLimit(Map<String, dynamic> discount) {
  return discount["product_limit"] == true;
}
