import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How a contract field is shown and edited.
enum _FieldKind { integer, text, date, boolean, nullableBoolean }

/// One row of the contract table.
class _ContractField {
  final String key;
  final String label;
  final _FieldKind kind;
  final bool editable;
  final bool nullable;

  const _ContractField(
    this.key,
    this.label,
    this.kind, {
    this.editable = true,
    this.nullable = false,
  });
}

/// Every field of the Contract model, in display order. The primary key and
/// the machine the contract belongs to are shown but read-only.
const List<_ContractField> _contractFields = [
  _ContractField('id', 'شناسه قرارداد', _FieldKind.integer, editable: false),
  _ContractField(
    'machine',
    'شناسه دستگاه',
    _FieldKind.integer,
    editable: false,
  ),
  _ContractField('model_type', 'نوع مدل (1 تا 3)', _FieldKind.integer),
  _ContractField('partner', 'شناسه همکار', _FieldKind.integer, nullable: true),
  _ContractField('start_date', 'تاریخ شروع (YYYY-MM-DD)', _FieldKind.date),
  _ContractField(
    'end_date',
    'تاریخ پایان (YYYY-MM-DD)',
    _FieldKind.date,
    nullable: true,
  ),
  _ContractField('city', 'شناسه شهر', _FieldKind.integer),
  _ContractField('location_category', 'نوع مکان (1 تا 3)', _FieldKind.integer),
  _ContractField('location', 'آدرس مکان', _FieldKind.text),
  _ContractField('daily_quota', 'سهمیه روزانه', _FieldKind.integer),
  _ContractField(
    'company_share_quota',
    'سهمیه سهم شرکت',
    _FieldKind.integer,
    nullable: true,
  ),
  _ContractField(
    'pos_receiver',
    'دریافت‌کننده پوز (1 یا 2)',
    _FieldKind.integer,
  ),
  _ContractField('pos_account', 'شناسه حساب بانکی پوز', _FieldKind.integer),
  _ContractField('deposit_amount', 'مبلغ ودیعه', _FieldKind.integer),
  _ContractField('assurance_amount', 'مبلغ ضمانت', _FieldKind.integer),
  _ContractField('allow_subscriptions', 'مجاز بودن اشتراک', _FieldKind.boolean),
  _ContractField(
    'can_partner_share_shrink',
    'کاهش سهم همکار با تخفیف',
    _FieldKind.nullableBoolean,
    nullable: true,
  ),
];

/// Table of the contract currently active for the selected machine. Editable
/// fields are saved together with the "save" button.
class ContractSettingsView extends ConsumerStatefulWidget {
  const ContractSettingsView({super.key});

  @override
  ConsumerState<ContractSettingsView> createState() =>
      _ContractSettingsViewState();
}

class _ContractSettingsViewState extends ConsumerState<ContractSettingsView> {
  Map<String, dynamic>? _contract;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool?> _boolValues = {};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _load(ref.read(activeMachineProvider));
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _boolValues.clear();
  }

  static bool _isBooleanKind(_FieldKind kind) =>
      kind == _FieldKind.boolean || kind == _FieldKind.nullableBoolean;

  static String _display(dynamic value) => value?.toString() ?? '';

  void _fill(Map<String, dynamic> contract) {
    _disposeControllers();
    for (final field in _contractFields) {
      if (_isBooleanKind(field.kind)) {
        _boolValues[field.key] = contract[field.key] as bool?;
      } else {
        _controllers[field.key] = TextEditingController(
          text: _display(contract[field.key]),
        );
      }
    }
  }

  Future<void> _load(String serial) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _message = null;
    });
    try {
      final response = await ProductService.getMachineContract(serial);
      if (!mounted || ref.read(activeMachineProvider) != serial) return;
      final contract = Map<String, dynamic>.from(response.data);
      _fill(contract);
      setState(() {
        _contract = contract;
        _isLoading = false;
      });
    } on DioException catch (e) {
      if (!mounted || ref.read(activeMachineProvider) != serial) return;
      setState(() {
        _contract = null;
        _isLoading = false;
        _loadError = e.response?.statusCode == 404
            ? 'قرارداد فعالی برای این دستگاه یافت نشد'
            : 'خطا در دریافت اطلاعات قرارداد از سرور';
      });
    }
  }

  /// Only the editable fields whose value differs from the stored contract.
  Map<String, dynamic> _changedValues() {
    final contract = _contract!;
    final changes = <String, dynamic>{};
    for (final field in _contractFields) {
      if (!field.editable) continue;
      if (_isBooleanKind(field.kind)) {
        final value = _boolValues[field.key];
        if (value != contract[field.key]) {
          changes[field.key] = value;
        }
        continue;
      }
      final text = _controllers[field.key]!.text.trim();
      if (text == _display(contract[field.key])) continue;
      // Nullable fields are cleared by sending an empty value.
      changes[field.key] = (text.isEmpty && field.nullable) ? null : text;
    }
    return changes;
  }

  Future<void> _save() async {
    final contract = _contract;
    if (contract == null || _isSaving) return;

    final changes = _changedValues();
    if (changes.isEmpty) {
      setState(() {
        _message = 'تغییری برای ذخیره وجود ندارد';
        _messageIsError = false;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      final response = await ProductService.updateContract(
        contract['id'] as int,
        changes,
      );
      if (!mounted) return;
      final updated = Map<String, dynamic>.from(response.data);
      _fill(updated);
      setState(() {
        _contract = updated;
        _isSaving = false;
        _message = 'تغییرات ذخیره شد';
        _messageIsError = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _message = _errorText(e);
        _messageIsError = true;
      });
    }
  }

  String _errorText(DioException e) {
    final data = e.response?.data;
    if (data is Map && data.isNotEmpty) {
      return data.entries
          .map((entry) {
            final value = entry.value;
            final text = value is List ? value.join(' ') : value.toString();
            return '${entry.key}: $text';
          })
          .join(' | ');
    }
    return 'خطا در ذخیره تغییرات';
  }

  Widget _cell(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: child,
  );

  Widget _valueWidget(_ContractField field) {
    if (!field.editable) {
      return Text(_display(_contract![field.key]));
    }
    return switch (field.kind) {
      _FieldKind.boolean => Switch(
        value: _boolValues[field.key] ?? false,
        onChanged: (value) {
          setState(() {
            _boolValues[field.key] = value;
          });
        },
      ),
      _FieldKind.nullableBoolean => DropdownButtonHideUnderline(
        child: DropdownButton<bool?>(
          value: _boolValues[field.key],
          items: const [
            DropdownMenuItem<bool?>(value: null, child: Text('ندارد')),
            DropdownMenuItem<bool?>(value: true, child: Text('بله')),
            DropdownMenuItem<bool?>(value: false, child: Text('خیر')),
          ],
          onChanged: (value) {
            setState(() {
              _boolValues[field.key] = value;
            });
          },
        ),
      ),
      _FieldKind.integer || _FieldKind.text || _FieldKind.date => TextField(
        controller: _controllers[field.key],
        keyboardType: field.kind == _FieldKind.integer
            ? const TextInputType.numberWithOptions(signed: true)
            : TextInputType.text,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: field.nullable ? 'خالی = ندارد' : null,
        ),
      ),
    };
  }

  TableRow _buildFieldRow(_ContractField field) {
    return TableRow(
      children: [
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(field.label),
              Text(field.key, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        _cell(_valueWidget(field)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reload the contract whenever another machine is selected.
    ref.listen<String>(activeMachineProvider, (_, serial) => _load(serial));
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final contract = _contract;
    if (contract == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_loadError ?? 'قرارداد یافت نشد'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _load(ref.read(activeMachineProvider)),
              child: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ویرایش قرارداد شماره ${contract['id']}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(320),
                    1: FlexColumnWidth(),
                  },
                  border: TableBorder(
                    horizontalInside: BorderSide(color: theme.dividerColor),
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      children: [
                        _cell(
                          const Text(
                            'فیلد',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        _cell(
                          const Text(
                            'مقدار',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    for (final field in _contractFields) _buildFieldRow(field),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_message != null)
                Expanded(
                  child: Text(
                    _message!,
                    style: TextStyle(
                      color: _messageIsError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                const Spacer(),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('ذخیره تغییرات'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
