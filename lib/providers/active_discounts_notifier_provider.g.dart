// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_discounts_notifier_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ActiveDiscountsNotifier)
const activeDiscountsProvider = ActiveDiscountsNotifierProvider._();

final class ActiveDiscountsNotifierProvider
    extends $NotifierProvider<ActiveDiscountsNotifier, List<Discount>> {
  const ActiveDiscountsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeDiscountsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeDiscountsNotifierHash();

  @$internal
  @override
  ActiveDiscountsNotifier create() => ActiveDiscountsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Discount> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Discount>>(value),
    );
  }
}

String _$activeDiscountsNotifierHash() =>
    r'1103c7468cf7b98dd427bf9e392f0f77ab813b9e';

abstract class _$ActiveDiscountsNotifier extends $Notifier<List<Discount>> {
  List<Discount> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<Discount>, List<Discount>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<Discount>, List<Discount>>,
              List<Discount>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
