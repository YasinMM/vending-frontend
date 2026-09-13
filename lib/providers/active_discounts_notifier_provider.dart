import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_discounts_notifier_provider.g.dart';

class Discount {
  final int id;
  final String code;
  final String name;
  final int companySharePercentage;
  final int? numericAmount;
  final int? percentageAmount;
  final int? percentageAmountLimit;
  final DateTime startDate;
  final DateTime? endDate;
  final int? quantityLimit;
  final int? perUserLimit;
  final bool machineLimit;
  final List<String> machineSerials;
  final bool productLimit;
  final List<String> productSerials;
  final bool isActive;
  final String? description;
  final bool pinned;
  bool selected;

  Discount({
    required this.id,
    required this.code,
    required this.name,
    required this.companySharePercentage,
    required this.numericAmount,
    required this.percentageAmount,
    required this.percentageAmountLimit,
    required this.startDate,
    this.endDate,
    required this.quantityLimit,
    required this.perUserLimit,
    required this.machineLimit,
    required this.machineSerials,
    required this.productLimit,
    required this.productSerials,
    required this.isActive,
    required this.description,
    required this.pinned,
    this.selected = false,
  });
}

@Riverpod(keepAlive: true)
class ActiveDiscountsNotifier extends _$ActiveDiscountsNotifier {
  @override
  List<Discount> build() {
    return [];
  }

  void setDiscounts(List<Discount> discounts) {
    state = discounts;
  }

  // void clear() {
  //   state = [];
  // }

  // void add(Product product) {
  //   final s = state;
  //   s.add(product);
  //   state = s;
  // }
}
