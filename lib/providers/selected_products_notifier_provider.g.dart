// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selected_products_notifier_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SelectedProductsNotifier)
const selectedProductsProvider = SelectedProductsNotifierProvider._();

final class SelectedProductsNotifierProvider
    extends $NotifierProvider<SelectedProductsNotifier, List<Product>> {
  const SelectedProductsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedProductsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedProductsNotifierHash();

  @$internal
  @override
  SelectedProductsNotifier create() => SelectedProductsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Product> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Product>>(value),
    );
  }
}

String _$selectedProductsNotifierHash() =>
    r'180cffb8e3de09275057c51939981655a9da267e';

abstract class _$SelectedProductsNotifier extends $Notifier<List<Product>> {
  List<Product> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<Product>, List<Product>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Product>, List<Product>>,
              List<Product>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
