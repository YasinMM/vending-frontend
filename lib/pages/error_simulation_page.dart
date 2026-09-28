import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/services/product_service.dart';

/// Submits a sensor reading so the server can detect critical values and
/// create the configured error log automatically.
class ErrorSimulationPage extends StatefulWidget {
  const ErrorSimulationPage({super.key});

  @override
  State<ErrorSimulationPage> createState() => _ErrorSimulationPageState();
}

class _ErrorSimulationPageState extends State<ErrorSimulationPage> {
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _sensors = [];

  Map<String, dynamic>? _selectedMachine;
  Map<String, dynamic>? _selectedSensor;
  final TextEditingController _amountController = TextEditingController();

  bool _isLoading = true;
  bool _isLoadingSensors = false;
  bool _isSubmitting = false;
  String? _loadError;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final machinesResponse = await ProductService.getMachineList();
      final machines = <Map<String, dynamic>>[];
      for (final machine in machinesResponse.data) {
        machines.add(Map<String, dynamic>.from(machine));
      }
      setState(() {
        _machines = machines;
        _isLoading = false;
      });
    } on DioException {
      setState(() {
        _isLoading = false;
        _loadError = 'خطا در دریافت اطلاعات از سرور';
      });
    }
  }

  Future<void> _selectMachine(Map<String, dynamic>? machine) async {
    setState(() {
      _selectedMachine = machine;
      _selectedSensor = null;
      _sensors = [];
      _resultMessage = null;
      _isLoadingSensors = machine != null;
    });
    if (machine == null) return;

    try {
      final response = await ProductService.getSensorList(
        machineSerial: machine['serial'].toString(),
      );
      final sensors = <Map<String, dynamic>>[];
      for (final sensor in response.data) {
        sensors.add(Map<String, dynamic>.from(sensor));
      }
      if (!mounted) return;
      setState(() {
        _sensors = sensors;
        _isLoadingSensors = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _sensors = [];
        _isLoadingSensors = false;
        _resultMessage = 'خطا در دریافت سنسورهای دستگاه';
      });
    }
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amountController.text.trim());
    if (_selectedMachine == null) {
      setState(() {
        _resultMessage = 'لطفاً دستگاه را انتخاب کنید';
      });
      return;
    }
    if (_selectedSensor == null) {
      setState(() {
        _resultMessage = 'لطفاً سنسور را انتخاب کنید';
      });
      return;
    }
    if (amount == null) {
      setState(() {
        _resultMessage = 'لطفاً مقدار عددی معتبر وارد کنید';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _resultMessage = null;
    });
    try {
      final response = await ProductService.createSensorData({
        'sensor': _selectedSensor!['id'],
        'amount': amount,
      });
      final data = Map<String, dynamic>.from(response.data);
      setState(() {
        if (data['critical'] == true && data['error_log_id'] != null) {
          _resultMessage = 'مقدار بحرانی بود؛ داده و لاگ خطا ثبت شدند';
        } else if (data['critical'] == true) {
          _resultMessage =
              'داده ثبت شد، اما برای این سنسور خطای بحرانی تنظیم نشده است';
        } else {
          _resultMessage = 'داده سنسور با موفقیت ثبت شد؛ مقدار بحرانی نیست';
        }
      });
    } on DioException {
      setState(() {
        _resultMessage = 'خطا در ثبت لاگ';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Widget _buildDropdown({
    required String label,
    required Map<String, dynamic>? value,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) itemText,
    required void Function(Map<String, dynamic>?) onChanged,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<Map<String, dynamic>>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<Map<String, dynamic>>(
              value: item,
              child: Text(itemText(item), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('شبیه‌سازی خطا در سرور'),
          centerTitle: true,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_loadError!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text('تلاش مجدد'),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildDropdown(
                            label: 'دستگاه',
                            value: _selectedMachine,
                            items: _machines,
                            itemText: (machine) =>
                                '${machine['serial']} - ${machine['name']}',
                            onChanged: _selectMachine,
                          ),
                          const SizedBox(height: 20),
                          if (_isLoadingSensors)
                            const Center(child: CircularProgressIndicator())
                          else
                            _buildDropdown(
                              label: 'سنسور',
                              value: _selectedSensor,
                              items: _sensors,
                              itemText: (s) =>
                                  '${s['serial']} - ${s['name']} (${s['unit']})',
                              onChanged: (value) => setState(() {
                                _selectedSensor = value;
                              }),
                              enabled:
                                  _selectedMachine != null &&
                                  _sensors.isNotEmpty,
                            ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'مقدار داده',
                              suffixText: _selectedSensor?['unit']?.toString(),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('ثبت داده سنسور'),
                          ),
                          if (_resultMessage != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _resultMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !_resultMessage!.contains('خطا')
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
