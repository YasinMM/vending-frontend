import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/machine_preference_service.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One row of the machine configuration table.
class _MachineField {
  final String key;
  final String label;
  final bool editable;
  final bool numeric;

  const _MachineField(
    this.key,
    this.label, {
    this.editable = true,
    this.numeric = false,
  });
}

/// Every field of the Machine model, in display order. The primary key is
/// shown but read-only.
const List<_MachineField> _machineFields = [
  _MachineField('id', 'شناسه', editable: false, numeric: true),
  _MachineField('creation_date', 'تاریخ ایجاد'),
  _MachineField('serial', 'سریال'),
  _MachineField('name', 'نام'),
  _MachineField('model', 'مدل'),
  _MachineField('manufacturer', 'سازنده'),
  _MachineField('status', 'وضعیت (شناسه)', numeric: true),
  _MachineField('location', 'مکان'),
  _MachineField('version', 'شناسه نسخه دستگاه', numeric: true),
  _MachineField('standby_time', 'زمان آماده‌باش (دقیقه)', numeric: true),
  _MachineField('cup_weight', 'وزن لیوان', numeric: true),
  _MachineField('boiler_temp_threshold', 'آستانه دمای بویلر', numeric: true),
];

/// Table of all fields of the currently selected machine. Editable fields are
/// saved together with the "save" button.
class MachineConfigurationView extends ConsumerStatefulWidget {
  const MachineConfigurationView({super.key});

  @override
  ConsumerState<MachineConfigurationView> createState() =>
      _MachineConfigurationViewState();
}

class _MachineConfigurationViewState
    extends ConsumerState<MachineConfigurationView> {
  Map<String, dynamic>? _machine;
  final Map<String, TextEditingController> _controllers = {};

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
  }

  void _fillControllers(Map<String, dynamic> machine) {
    _disposeControllers();
    for (final field in _machineFields) {
      _controllers[field.key] = TextEditingController(
        text: _display(machine[field.key]),
      );
    }
  }

  static String _display(dynamic value) => value?.toString() ?? '';

  Future<void> _load(String serial) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ProductService.getMachineList();
      Map<String, dynamic>? machine;
      final data = response.data;
      if (data is List) {
        for (final item in data) {
          if (item is Map && item['serial']?.toString() == serial) {
            machine = Map<String, dynamic>.from(item);
            break;
          }
        }
      }
      if (!mounted || ref.read(activeMachineProvider) != serial) return;
      if (machine == null) {
        setState(() {
          _machine = null;
          _isLoading = false;
          _loadError = 'دستگاه یافت نشد';
        });
        return;
      }
      _fillControllers(machine);
      setState(() {
        _machine = machine;
        _isLoading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'خطا در دریافت اطلاعات دستگاه از سرور';
      });
    }
  }

  /// Only the editable fields whose text differs from the stored value.
  Map<String, dynamic> _changedValues() {
    final machine = _machine!;
    final changes = <String, dynamic>{};
    for (final field in _machineFields) {
      if (!field.editable) continue;
      final text = _controllers[field.key]!.text.trim();
      if (text == _display(machine[field.key])) continue;
      // version is nullable: an empty value unsets it.
      changes[field.key] = (field.key == 'version' && text.isEmpty)
          ? null
          : text;
    }
    return changes;
  }

  Future<void> _save() async {
    final machine = _machine;
    if (machine == null || _isSaving) return;

    final changes = _changedValues();
    if (changes.isEmpty) {
      setState(() {
        _message = 'تغییری برای ذخیره وجود ندارد';
        _messageIsError = false;
      });
      return;
    }

    final oldSerial = machine['serial'].toString();
    setState(() {
      _isSaving = true;
      _message = null;
    });
    try {
      final response = await ProductService.updateMachine(oldSerial, changes);
      if (!mounted) return;
      final updated = Map<String, dynamic>.from(response.data);
      final newSerial = updated['serial'].toString();
      _fillControllers(updated);
      setState(() {
        _machine = updated;
        _isSaving = false;
        _message = 'تغییرات ذخیره شد';
        _messageIsError = false;
      });
      if (newSerial != oldSerial) {
        // The edited machine is the active one, so follow its new serial.
        // The listener in build reloads this table for the new serial.
        ref.read(activeMachineProvider.notifier).setMachine(newSerial);
        await MachinePreferenceService.save(newSerial);
      }
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

  TableRow _buildFieldRow(_MachineField field) {
    final controller = _controllers[field.key]!;
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
        _cell(
          field.editable
              ? TextField(
                  controller: controller,
                  keyboardType: field.numeric
                      ? const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        )
                      : TextInputType.text,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                )
              : Text(controller.text),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reload the table whenever another machine is selected.
    ref.listen<String>(activeMachineProvider, (_, serial) => _load(serial));
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final machine = _machine;
    if (machine == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_loadError ?? 'دستگاه یافت نشد'),
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
            'ویرایش مشخصات دستگاه ${machine['serial']}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                child: Table(
                  columnWidths: const {
                    0: FixedColumnWidth(300),
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
                    for (final field in _machineFields) _buildFieldRow(field),
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
