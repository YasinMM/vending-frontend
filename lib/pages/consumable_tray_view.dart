import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/providers/active_machine_notifier_provider.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Table of the consumables of the currently selected machine. Each consumable
/// can be assigned to one of the machine's sensors or left unassigned. Changes
/// are saved as soon as a new sensor is picked.
class ConsumableTrayView extends ConsumerStatefulWidget {
  const ConsumableTrayView({super.key});

  @override
  ConsumerState<ConsumableTrayView> createState() => _ConsumableTrayViewState();
}

class _ConsumableTrayViewState extends ConsumerState<ConsumableTrayView> {
  List<Map<String, dynamic>> _consumables = [];
  List<Map<String, dynamic>> _sensors = [];
  final Set<int> _savingIds = {};

  bool _isLoading = true;
  String? _loadError;
  String? _message;
  bool _messageIsError = false;

  static const List<double> _columnWidths = [280, 160, 200, 360];

  @override
  void initState() {
    super.initState();
    _load(ref.read(activeMachineProvider));
  }

  Future<void> _load(String serial) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
      _message = null;
    });
    try {
      final responses = await Future.wait([
        ProductService.getMachineConsumableAssignments(serial),
        ProductService.getSensorList(machineSerial: serial),
      ]);
      final consumables = [
        for (final item in responses[0].data as List)
          Map<String, dynamic>.from(item),
      ];
      final sensors = [
        for (final item in responses[1].data as List)
          Map<String, dynamic>.from(item),
      ];
      if (!mounted || ref.read(activeMachineProvider) != serial) return;
      setState(() {
        _consumables = consumables;
        _sensors = sensors;
        _isLoading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'خطا در دریافت اطلاعات مواد مصرفی از سرور';
      });
    }
  }

  Future<void> _assign(Map<String, dynamic> row, int? sensorId) async {
    final id = row['id'] as int;
    final previous = row['machine_sensor'] as int?;
    if (_savingIds.contains(id) || previous == sensorId) return;

    setState(() {
      row['machine_sensor'] = sensorId;
      _savingIds.add(id);
      _message = null;
    });
    try {
      await ProductService.updateMachineConsumableSensor(id, sensorId);
      if (!mounted) return;
      setState(() {
        _savingIds.remove(id);
        _messageIsError = false;
        _message = sensorId == null
            ? 'تخصیص «${row['consumable_name']}» حذف شد'
            : 'سنسور برای «${row['consumable_name']}» ثبت شد';
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        row['machine_sensor'] = previous;
        _savingIds.remove(id);
        _messageIsError = true;
        _message = 'خطا در ثبت تخصیص سنسور «${row['consumable_name']}»';
      });
    }
  }

  Widget _headerCell(String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
  );

  Widget _tableCell(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: child,
  );

  Widget _sensorDropdown(Map<String, dynamic> row) {
    final id = row['id'] as int;
    final current = row['machine_sensor'] as int?;
    final hasSensor = _sensors.any((sensor) => sensor['id'] == current);
    return SizedBox(
      width: 320,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          value: hasSensor ? current : null,
          hint: const Text('تخصیص داده نشده'),
          onChanged: _savingIds.contains(id)
              ? null
              : (sensorId) => _assign(row, sensorId),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('تخصیص داده نشده'),
            ),
            for (final sensor in _sensors)
              DropdownMenuItem<int?>(
                value: sensor['id'] as int,
                child: Text('${sensor['name']} (${sensor['serial']})'),
              ),
          ],
        ),
      ),
    );
  }

  TableRow _buildConsumableRow(Map<String, dynamic> row) {
    return TableRow(
      children: [
        _tableCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(row['consumable_name']?.toString() ?? ''),
              Text(
                row['consumable_serial']?.toString() ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _tableCell(Text(row['unit']?.toString() ?? '')),
        _tableCell(Text(row['amount']?.toString() ?? '')),
        _tableCell(_sensorDropdown(row)),
      ],
    );
  }

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

  @override
  Widget build(BuildContext context) {
    // Reload the table whenever another machine is selected.
    ref.listen<String>(activeMachineProvider, (_, serial) => _load(serial));
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_loadError!),
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
            'هر ماده مصرفی را می‌توانید به یکی از سنسورهای دستگاه تخصیص دهید '
            'یا بدون تخصیص نگه دارید.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_consumables.isEmpty)
            const Expanded(
              child: Center(child: Text('ماده مصرفی برای این دستگاه یافت نشد')),
            )
          else
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildTable([
                      TableRow(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        children: [
                          _headerCell('ماده مصرفی'),
                          _headerCell('واحد'),
                          _headerCell('موجودی'),
                          _headerCell('سنسور تخصیص‌یافته'),
                        ],
                      ),
                      for (final row in _consumables) _buildConsumableRow(row),
                    ]),
                  ),
                ),
              ),
            ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(
              _message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _messageIsError
                    ? colorScheme.error
                    : colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
