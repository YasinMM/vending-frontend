import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_production_test/widgets/machine_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Displays the latest reading for each sensor and lets users submit new ones.
class ErrorSimulationPage extends ConsumerStatefulWidget {
  const ErrorSimulationPage({super.key});

  @override
  ConsumerState<ErrorSimulationPage> createState() =>
      _ErrorSimulationPageState();
}

class _ErrorSimulationPageState extends ConsumerState<ErrorSimulationPage> {
  List<Map<String, dynamic>> _sensors = [];
  final Map<int, TextEditingController> _valueControllers = {};
  final Map<int, FocusNode> _valueFocusNodes = {};
  final Map<int, String> _savedValues = {};
  final Set<int> _savingSensorIds = {};

  bool _isLoadingSensors = true;
  String? _loadError;
  String? _resultMessage;
  String? _sortColumn;
  bool _sortAscending = true;

  static const List<double> _columnWidths = [180, 220, 260, 260, 200, 240];
  static const double _minimumTableWidth = 1360;
  static final RegExp _decimalTrailingZeros = RegExp(r'(\.\d*?[1-9])0+$|\.0+$');

  @override
  void initState() {
    super.initState();
    _loadSensors(ref.read(activeMachineProvider));
  }

  @override
  void dispose() {
    _disposeRowEditors();
    super.dispose();
  }

  void _disposeRowEditors() {
    for (final controller in _valueControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _valueFocusNodes.values) {
      focusNode.dispose();
    }
    _valueControllers.clear();
    _valueFocusNodes.clear();
    _savedValues.clear();
  }

  Future<void> _loadSensors(String machineSerial) async {
    setState(() {
      _isLoadingSensors = true;
      _loadError = null;
      _resultMessage = null;
    });
    try {
      final response = await ProductService.getSensorList(
        machineSerial: machineSerial,
      );
      final sensors = <Map<String, dynamic>>[];
      for (final sensor in response.data) {
        sensors.add(Map<String, dynamic>.from(sensor));
      }
      if (!mounted || ref.read(activeMachineProvider) != machineSerial) return;

      _disposeRowEditors();
      for (final sensor in sensors) {
        final id = sensor['id'] as int;
        final value = sensor['last_value'] == null
            ? ''
            : _formatAmount(sensor['last_value']);
        _savedValues[id] = value;
        _valueControllers[id] = TextEditingController(text: value);
        final focusNode = FocusNode();
        focusNode.addListener(() {
          if (!focusNode.hasFocus) _saveSensorValue(sensor);
        });
        _valueFocusNodes[id] = focusNode;
      }

      setState(() {
        _sensors = sensors;
        _isLoadingSensors = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _isLoadingSensors = false;
        _loadError = 'خطا در دریافت اطلاعات سنسورها از سرور';
      });
    }
  }

  Future<void> _saveSensorValue(Map<String, dynamic> sensor) async {
    final sensorId = sensor['id'] as int;
    if (_savingSensorIds.contains(sensorId)) return;

    final controller = _valueControllers[sensorId];
    if (controller == null) return;
    final valueText = controller.text.trim();
    if (valueText == (_savedValues[sensorId] ?? '')) return;

    final amount = num.tryParse(valueText);
    if (amount == null) {
      setState(() {
        _resultMessage =
            'مقدار واردشده برای سنسور «${sensor['name']}» معتبر نیست';
      });
      return;
    }

    setState(() {
      _savingSensorIds.add(sensorId);
      _resultMessage = 'در حال ثبت مقدار سنسور...';
    });
    try {
      await ProductService.createSensorData({
        'machine_sensor': sensorId,
        'amount': amount,
      });
      if (!mounted) return;
      _savedValues[sensorId] = valueText;
      setState(() {
        sensor['last_value'] = _formatAmount(valueText);
        sensor['last_received'] = DateTime.now().toIso8601String();
        _resultMessage = 'مقدار «${sensor['name']}» ثبت شد';
      });
    } on DioException {
      if (mounted) {
        setState(() {
          _resultMessage = 'خطا در ثبت مقدار سنسور «${sensor['name']}»';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingSensorIds.remove(sensorId);
        });
        if (_valueControllers[sensorId]?.text.trim() !=
            _savedValues[sensorId]) {
          _saveSensorValue(sensor);
        }
      }
    }
  }

  String _formatRange(
    Map<String, dynamic> sensor,
    String minKey,
    String maxKey,
  ) {
    final minimum = _formatAmount(sensor[minKey]);
    final maximum = _formatAmount(sensor[maxKey]);
    final unit = sensor['unit']?.toString();
    final range = '$minimum – $maximum';
    return unit == null || unit.isEmpty ? range : '$range $unit';
  }

  String _formatAmount(dynamic value) {
    if (value == null) return 'ندارد';
    final text = value.toString();
    if (!text.contains('.')) return text;
    return text.replaceFirstMapped(
      _decimalTrailingZeros,
      (match) => match.group(1) ?? '',
    );
  }

  String _formatLastReceived(dynamic value) {
    if (value == null) return 'داده‌ای ثبت نشده';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return DateFormat('yyyy/MM/dd HH:mm:ss').format(date.toLocal());
  }

  void _sortSensors(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _sensors.sort((left, right) {
        if (column == 'last_received') {
          final leftDate = DateTime.tryParse(left[column]?.toString() ?? '');
          final rightDate = DateTime.tryParse(right[column]?.toString() ?? '');
          final result = leftDate == null || rightDate == null
              ? leftDate == rightDate
                    ? 0
                    : leftDate == null
                    ? -1
                    : 1
              : leftDate.compareTo(rightDate);
          return _sortAscending ? result : -result;
        }
        final leftValue = left[column]?.toString().toLowerCase() ?? '';
        final rightValue = right[column]?.toString().toLowerCase() ?? '';
        final result = leftValue.compareTo(rightValue);
        return _sortAscending ? result : -result;
      });
    });
  }

  Widget _headerCell(String label, {String? sortKey}) {
    final sorted = sortKey != null && _sortColumn == sortKey;
    return InkWell(
      onTap: sortKey == null ? null : () => _sortSensors(sortKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (sortKey != null) ...[
              const SizedBox(width: 4),
              Icon(
                sorted
                    ? (_sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward)
                    : Icons.unfold_more,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tableCell(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: child,
  );

  Table _buildTable(List<TableRow> rows) => Table(
    columnWidths: {
      for (var index = 0; index < _columnWidths.length; index++)
        index: FixedColumnWidth(_columnWidths[index]),
    },
    border: TableBorder(
      horizontalInside: BorderSide(color: Theme.of(context).dividerColor),
    ),
    children: rows,
  );

  TableRow _buildHeaderRow(Color headerColor) => TableRow(
    decoration: BoxDecoration(color: headerColor),
    children: [
      _headerCell('سریال سنسور', sortKey: 'serial'),
      _headerCell('نام سنسور', sortKey: 'name'),
      _headerCell('محدوده مجاز'),
      _headerCell('محدوده بحرانی'),
      _headerCell('آخرین مقدار'),
      _headerCell('زمان دریافت آخرین داده', sortKey: 'last_received'),
    ],
  );

  TableRow _buildSensorRow(Map<String, dynamic> sensor) {
    final id = sensor['id'] as int;
    final saving = _savingSensorIds.contains(id);
    return TableRow(
      children: [
        _tableCell(Text(sensor['serial']?.toString() ?? '')),
        _tableCell(Text(sensor['name']?.toString() ?? '')),
        _tableCell(Text(_formatRange(sensor, 'min_value', 'max_value'))),
        _tableCell(Text(_formatRange(sensor, 'critical_min', 'critical_max'))),
        _tableCell(
          SizedBox(
            width: 180,
            child: TextField(
              controller: _valueControllers[id],
              focusNode: _valueFocusNodes[id],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveSensorValue(sensor),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ثبت نشده',
                suffixText: sensor['unit']?.toString(),
                border: const OutlineInputBorder(),
                suffixIcon: saving
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
        _tableCell(Text(_formatLastReceived(sensor['last_received']))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: .rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شبیه‌سازی خطا در سرور'),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Center(child: MachineSelector(onChanged: _loadSensors)),
            ),
          ],
        ),
        body: _isLoadingSensors
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_loadError!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          _loadSensors(ref.read(activeMachineProvider)),
                      child: const Text('تلاش مجدد'),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'برای ثبت داده جدید، مقدار هر سنسور را ویرایش کنید؛ '
                      'با زدن Enter یا خروج از فیلد ذخیره می‌شود.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_sensors.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('سنسوری برای این دستگاه یافت نشد'),
                        ),
                      )
                    else
                      Expanded(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final tableWidth =
                                  constraints.maxWidth < _minimumTableWidth
                                  ? _minimumTableWidth
                                  : constraints.maxWidth;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: tableWidth,
                                  height: constraints.maxHeight,
                                  child: Column(
                                    children: [
                                      _buildTable([
                                        _buildHeaderRow(
                                          colorScheme.surfaceContainerHighest,
                                        ),
                                      ]),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: _buildTable(
                                            _sensors
                                                .map(_buildSensorRow)
                                                .toList(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    if (_resultMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _resultMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color:
                              _resultMessage!.startsWith('خطا') ||
                                  _resultMessage!.contains('معتبر نیست')
                              ? colorScheme.error
                              : colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
