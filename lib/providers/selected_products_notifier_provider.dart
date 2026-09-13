import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selected_products_notifier_provider.g.dart';


class Product {
  final int id;
  final String name;
  final String serial;
  final int type;
  final int companyShare;
  final int parnterShare;
  final double companyDoubleRate;
  final double partnerDoubleRate;
  int quantity;

  Product({
    required this.id,
    required this.name,
    required this.serial,
    required this.type,
    required this.companyShare,
    required this.parnterShare,
    required this.companyDoubleRate,
    required this.partnerDoubleRate,
    this.quantity = 0,
  });
}

@Riverpod(keepAlive: true)
class SelectedProductsNotifier extends _$SelectedProductsNotifier {
  @override
  List<Product> build() {
    return [];
  }

  void setProducts(List<Product> products){
    state = products;
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
