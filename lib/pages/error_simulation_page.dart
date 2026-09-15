import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/services/product_service.dart';

/// A page for simulating server errors. It fetches the error dictionary,
/// machine and sensor records and lets the user create a new Error Log record.
class ErrorSimulationPage extends StatefulWidget {
  const ErrorSimulationPage({super.key});

  @override
  State<ErrorSimulationPage> createState() => _ErrorSimulationPageState();
}

class _ErrorSimulationPageState extends State<ErrorSimulationPage> {
  List<Map<String, dynamic>> _errors = [];
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _sensors = [];

  Map<String, dynamic>? _selectedError;
  Map<String, dynamic>? _selectedMachine;
  Map<String, dynamic>? _selectedSensor;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _resultMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final errorsResponse = await ProductService.getErrorDictionaryList();
      final machinesResponse = await ProductService.getMachineList();
      List<Map<String, dynamic>> errors = [];
      List<Map<String, dynamic>> machines = [];
      for (var e in errorsResponse.data) {
        errors.add(Map<String, dynamic>.from(e));
      }
      for (var m in machinesResponse.data) {
        machines.add(Map<String, dynamic>.from(m));
      }
      setState(() {
        _errors = errors;
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

  Future<void> _loadSensors(String machineSerial) async {
    try {
      final response = await ProductService.getSensorList(machineSerial: machineSerial);
      List<Map<String, dynamic>> sensors = [];
      for (var s in response.data) {
        sensors.add(Map<String, dynamic>.from(s));
      }
      setState(() {
        _sensors = sensors;
        _selectedSensor = null;
      });
    } on DioException {
      setState(() {
        _sensors = [];
        _selectedSensor = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedError == null) {
      setState(() {
        _resultMessage = 'لطفاً نوع خطا را انتخاب کنید';
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _resultMessage = null;
    });
    try {
      await ProductService.createErrorLog({
        'error': _selectedError!['id'],
        'machine': _selectedMachine?['id'],
        'sensor': _selectedSensor?['id'],
      });
      setState(() {
        _resultMessage = 'لاگ خطا با موفقیت ثبت شد';
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
                                label: 'نوع خطا',
                                value: _selectedError,
                                items: _errors,
                                itemText: (e) =>
                                    '${e['error_code']} - ${e['user_message']}',
                                onChanged: (value) => setState(() {
                                  _selectedError = value;
                                }),
                              ),
                              const SizedBox(height: 20),
                              _buildDropdown(
                                label: 'دستگاه (اختیاری)',
                                value: _selectedMachine,
                                items: _machines,
                                itemText: (m) =>
                                    '${m['serial']} - ${m['name']}',
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMachine = value;
                                    _selectedSensor = null;
                                    _sensors = [];
                                  });
                                  if (value != null) {
                                    _loadSensors(value['serial']);
                                  }
                                },
                              ),
                              const SizedBox(height: 20),
                              _buildDropdown(
                                label: 'سنسور (اختیاری)',
                                value: _selectedSensor,
                                items: _sensors,
                                itemText: (s) =>
                                    '${s['serial']} - ${s['name']}',
                                onChanged: (value) => setState(() {
                                  _selectedSensor = value;
                                }),
                                enabled: _selectedMachine != null,
                              ),
                              const SizedBox(height: 32),
                              ElevatedButton(
                                onPressed:
                                    _isSubmitting ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
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
                                    : const Text('ثبت لاگ خطا'),
                              ),
                              if (_resultMessage != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  _resultMessage!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _resultMessage!.contains('موفقیت')
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
