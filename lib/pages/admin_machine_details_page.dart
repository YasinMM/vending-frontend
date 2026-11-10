import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/services/admin_auth_session.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:go_router/go_router.dart';

class AdminMachineDetailsPage extends StatefulWidget {
  const AdminMachineDetailsPage({super.key, required this.machineSerial});

  static const String routePath = '/admin/machines';

  final String machineSerial;

  @override
  State<AdminMachineDetailsPage> createState() =>
      _AdminMachineDetailsPageState();
}

class _AdminMachineDetailsPageState extends State<AdminMachineDetailsPage> {
  static const int _pageSize = 20;
  static const List<(String, String, IconData)> _sections = [
    ('overview', 'نمای کلی', Icons.dashboard_outlined),
    ('inventory', 'موجودی', Icons.inventory_2_outlined),
    ('contracts', 'قراردادها', Icons.description_outlined),
    ('purchases', 'خریدها', Icons.receipt_long_outlined),
    ('sensors', 'سنسورها', Icons.sensors_outlined),
    ('components', 'قطعات', Icons.memory_outlined),
    ('discounts', 'تخفیف‌ها', Icons.sell_outlined),
    ('operations', 'عملیات', Icons.support_agent_outlined),
    ('errors', 'خطاها', Icons.warning_amber_outlined),
  ];

  final Map<String, Map<String, dynamic>> _sectionData = {};
  Map<String, dynamic>? _machineData;
  final Map<String, String> _sectionErrors = {};
  final Map<String, int> _nextOffsets = {};
  final Set<String> _loadingSections = {};
  bool _prefetchStarted = false;
  int _selectedSectionIndex = 0;

  bool get _isAuthenticated => AdminAuthSession.isAuthenticated;

  @override
  void initState() {
    super.initState();
    if (_isAuthenticated) {
      _loadSection('overview');
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/admin/machines');
      });
    }
  }

  Future<void> _loadSection(
    String section, {
    bool refresh = false,
    bool loadMore = false,
  }) async {
    if (!_isAuthenticated) return;
    if (_loadingSections.contains(section)) return;
    if (!refresh && !loadMore && _sectionData.containsKey(section)) return;

    final offset = loadMore ? (_nextOffsets[section] ?? 0) : 0;
    setState(() {
      _loadingSections.add(section);
      _sectionErrors.remove(section);
      if (refresh) _nextOffsets.remove(section);
    });
    try {
      final response = await ProductService.getAdminMachineDetails(
        widget.machineSerial,
        section: section,
        offset: offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      final responseData = Map<String, dynamic>.from(response.data);
      final machine = responseData['machine'];
      final incoming = Map<String, dynamic>.from(
        responseData['data'] as Map? ?? responseData,
      );
      final current = _sectionData[section];
      final merged = loadMore && current != null
          ? _mergePages(current, incoming)
          : incoming;
      setState(() {
        if (machine is Map) {
          _machineData = Map<String, dynamic>.from(machine);
        }
        _sectionData[section] = merged;
        if (_hasMore(incoming)) {
          _nextOffsets[section] = offset + _pageSize;
        }
        _loadingSections.remove(section);
      });
      if (section == 'overview' && !_prefetchStarted) {
        _prefetchStarted = true;
        unawaited(_prefetchRemainingSections());
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSections.remove(section);
        _sectionErrors[section] = error.response?.statusCode == 401
            ? 'نشست ورود منقضی شد؛ دوباره وارد شوید'
            : 'خطا در دریافت اطلاعات این بخش';
      });
      if (error.response?.statusCode == 401) {
        AdminAuthSession.clear();
        context.go('/admin/machines');
      }
    }
  }

  Future<void> _prefetchRemainingSections() async {
    await Future.wait(
      _sections
          .map((section) => section.$1)
          .where((section) => section != 'overview')
          .map(_loadSection),
    );
  }

  Future<Map<String, dynamic>> _updateRecord(
    String resource,
    int recordId,
    Map<String, dynamic> values,
  ) async {
    final response = await ProductService.updateAdminMachineRecord(
      widget.machineSerial,
      resource: resource,
      recordId: recordId,
      data: values,
    );
    final updated = Map<String, dynamic>.from(response.data);
    if (resource == 'machine' &&
        updated['serial']?.toString() != widget.machineSerial &&
        mounted) {
      context.go(
        '${AdminMachineDetailsPage.routePath}/'
        '${Uri.encodeComponent(updated['serial'].toString())}',
      );
    }
    if (!mounted) return updated;
    setState(() {
      if (resource == 'machine') {
        _machineData = {...?_machineData, ...updated};
      }
      for (final section in _sectionData.keys.toList()) {
        _sectionData[section] = Map<String, dynamic>.from(
          _replaceRecord(_sectionData[section]!, resource, recordId, updated)
              as Map,
        );
      }
    });
    return updated;
  }

  dynamic _replaceRecord(
    dynamic value,
    String resource,
    int recordId,
    Map<String, dynamic> updated,
  ) {
    if (value is List) {
      return value
          .map((item) => _replaceRecord(item, resource, recordId, updated))
          .toList();
    }
    if (value is Map) {
      if (value['__resource'] == resource && value['id'] == recordId) {
        return {...value, ...updated};
      }
      return value.map(
        (key, item) => MapEntry(
          key.toString(),
          _replaceRecord(item, resource, recordId, updated),
        ),
      );
    }
    return value;
  }

  Map<String, dynamic> _mergePages(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
  ) {
    final merged = <String, dynamic>{...current};
    for (final entry in incoming.entries) {
      final oldValue = current[entry.key];
      final newValue = entry.value;
      if (oldValue is Map &&
          newValue is Map &&
          oldValue['items'] is List &&
          newValue['items'] is List) {
        merged[entry.key] = {
          ...Map<String, dynamic>.from(newValue),
          'items': [
            ...List<dynamic>.from(oldValue['items']),
            ...List<dynamic>.from(newValue['items']),
          ],
        };
      } else if (oldValue is Map && newValue is Map) {
        merged[entry.key] = _mergePages(
          Map<String, dynamic>.from(oldValue),
          Map<String, dynamic>.from(newValue),
        );
      } else {
        merged[entry.key] = newValue;
      }
    }
    return merged;
  }

  bool _hasMore(dynamic value) {
    if (value is Map) {
      if (value['has_more'] == true) return true;
      return value.values.any(_hasMore);
    }
    if (value is List) return value.any(_hasMore);
    return false;
  }

  void _signOut() {
    AdminAuthSession.clear();
    setState(() {
      _sectionData.clear();
      _machineData = null;
      _sectionErrors.clear();
      _nextOffsets.clear();
      _prefetchStarted = false;
    });
    context.go('/admin/machines');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: .rtl,
      child: DefaultTabController(
        length: _sections.length,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Flexible(child: Text('دستگاه ${widget.machineSerial}')),
                IconButton(
                  tooltip: 'بروزرسانی بخش',
                  onPressed:
                      _loadingSections.contains(
                        _sections[_selectedSectionIndex].$1,
                      )
                      ? null
                      : () => _loadSection(
                          _sections[_selectedSectionIndex].$1,
                          refresh: true,
                        ),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            actions: [
              if (_isAuthenticated)
                IconButton(
                  tooltip: 'خروج از پنل',
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                ),
              const SizedBox(width: 8),
            ],
            bottom: _isAuthenticated
                ? TabBar(
                    isScrollable: true,
                    tabs: [
                      for (final section in _sections)
                        Tab(icon: Icon(section.$3), text: section.$2),
                    ],
                    onTap: (index) {
                      setState(() => _selectedSectionIndex = index);
                      _loadSection(_sections[index].$1);
                    },
                  )
                : null,
          ),
          body: _isAuthenticated
              ? TabBarView(
                  children: [
                    for (final section in _sections)
                      _AdminSectionView(
                        machineSerial: widget.machineSerial,
                        machineRecord: _machineData,
                        title: section.$2,
                        payload:
                            section.$1 == 'overview' &&
                                _sectionData[section.$1] != null
                            ? {
                                'machine': _machineData ?? {},
                                ..._sectionData[section.$1]!,
                              }
                            : _sectionData[section.$1],
                        error: _sectionErrors[section.$1],
                        isLoading: _loadingSections.contains(section.$1),
                        onRetry: () => _loadSection(section.$1, refresh: true),
                        onRefresh: () =>
                            _loadSection(section.$1, refresh: true),
                        onLoadMore: () =>
                            _loadSection(section.$1, loadMore: true),
                        onUpdateRecord: _updateRecord,
                      ),
                  ],
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

class _AdminSectionView extends StatelessWidget {
  const _AdminSectionView({
    required this.machineSerial,
    required this.machineRecord,
    required this.title,
    required this.payload,
    required this.error,
    required this.isLoading,
    required this.onRetry,
    required this.onLoadMore,
    required this.onRefresh,
    required this.onUpdateRecord,
  });

  final String machineSerial;
  final Map<String, dynamic>? machineRecord;
  final String title;
  final Map<String, dynamic>? payload;
  final String? error;
  final bool isLoading;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onRefresh;
  final Future<Map<String, dynamic>> Function(
    String resource,
    int recordId,
    Map<String, dynamic> values,
  )
  onUpdateRecord;

  @override
  Widget build(BuildContext context) {
    if (payload == null && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (payload == null || error != null) {
return Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? 'اطلاعات این بخش هنوز بارگذاری نشده است'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'بروزرسانی $title',
                  onPressed: isLoading ? null : onRetry,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final entry in payload!.entries)
              if (!const {
                'has_more',
                'offset',
                'limit',
                'total',
              }.contains(entry.key))
                _renderSectionData(
                  context,
                  entry.key,
                  entry.value,
                  isLoading: isLoading,
                ),
          ],
        ),
        if (isLoading && payload != null)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _renderSectionData(
    BuildContext context,
    String label,
    dynamic value, {
    bool isLoading = false,
  }) {
    final title = _label(label);
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map['items'] is List) {
        final rows = (map['items'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        return _recordsTable(
          context,
          title,
          rows,
          total: map['total'],
          hasMore: map['has_more'] == true,
          isLoading: isLoading,
        );
      }
      if (map.containsKey('__resource')) {
        return _recordsTable(context, title, [map]);
      }
      if (map.isNotEmpty) {
        return _recordsTable(context, title, [map]);
      }
      return const SizedBox.shrink();
    }
    if (value is List) {
      final rows = value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (rows.isNotEmpty) return _recordsTable(context, title, rows);
      return _recordsTable(
        context,
        title,
        value.map((item) => {'value': item}).toList(),
      );
    }
    return _recordsTable(context, title, [
      {'value': value},
    ]);
  }

  Widget _recordsTable(
    BuildContext context,
    String title,
    List<Map<String, dynamic>> records, {
    dynamic total,
    bool hasMore = false,
    bool isLoading = false,
  }) {
    return _AdminRecordsTable(
      title: title,
      records: records,
      total: total,
      hasMore: hasMore,
      isLoading: isLoading,
      onLoadMore: onLoadMore,
      onRefresh: onRefresh,
      flattenRecord: _flattenRecord,
      labelFor: _label,
      onEdit: (record) => _editRecord(context, title, record),
    );
  }

  Map<String, dynamic> _flattenRecord(Map<String, dynamic> record) {
    final flattened = <String, dynamic>{};
    void addValue(
      String prefix,
      dynamic value, {
      Map<String, dynamic> choices = const {},
      String? fieldName,
    }) {
      if (value is Map) {
        if (value['__resource'] is String) {
          flattened[prefix] = _RelatedRecords(
            _label(prefix.split(' · ').last),
            [Map<String, dynamic>.from(value)],
            parentRecord: record,
            parentField: prefix,
          );
          return;
        }
        final displayValues = value['__field_display'] is Map
            ? Map<String, dynamic>.from(value['__field_display'] as Map)
            : const <String, dynamic>{};
        final nestedChoices = value['__field_choices'] is Map
            ? Map<String, dynamic>.from(value['__field_choices'] as Map)
            : const <String, dynamic>{};
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (!key.startsWith('__')) {
            addValue(
              prefix.isEmpty ? key : '$prefix · $key',
              displayValues.containsKey(key) ? displayValues[key] : entry.value,
              choices: nestedChoices,
              fieldName: key,
            );
          }
        }
      } else if (value is List) {
        final relatedRecords = value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        flattened[prefix] = relatedRecords.isNotEmpty
            ? _RelatedRecords(
                _label(prefix.split(' · ').last),
                relatedRecords,
                parentRecord: record,
                parentField: prefix,
              )
            : value.map(_displayValue).join('، ');
      } else if (value is String) {
        final decoded = _decodeRecordList(value);
        if (decoded != null && decoded.isNotEmpty) {
          flattened[prefix] = _RelatedRecords(
            _label(prefix.split(' · ').last),
            decoded,
            parentRecord: record,
            parentField: prefix,
          );
        } else {
          flattened[prefix] = value;
        }
      } else {
        final choice = fieldName == null || choices[fieldName] is! Map
            ? null
            : (choices[fieldName] as Map)[value?.toString()];
        flattened[prefix] = choice?.toString() ?? value?.toString() ?? '—';
      }
    }

    final relationDisplays = record['__relation_display'] is Map
        ? Map<String, dynamic>.from(record['__relation_display'] as Map)
        : const <String, dynamic>{};
    final hasLinkedSensor = record['sensor'] is Map;
    for (final entry in record.entries) {
      if (entry.key == 'sensor') continue;
      if (entry.key == 'product') {
        final machineProduct = record['machine_product'];
        final productRecord =
            entry.value is Map &&
                (entry.value as Map)['__resource'] == 'product'
            ? entry.value
            : machineProduct is Map && machineProduct['product'] is Map
            ? machineProduct['product']
            : null;
        if (productRecord is Map && productRecord['__resource'] == 'product') {
          flattened[entry.key] = _RelatedRecords(
            _label('product'),
            [Map<String, dynamic>.from(productRecord)],
            parentRecord: record,
            parentField: entry.key,
          );
          continue;
        }
      }
      final relationName = entry.key.endsWith('_id')
          ? entry.key.substring(0, entry.key.length - 3)
          : null;
      final relatedValue = relationName == null
          ? null
          : record[relationName] ??
                (relationName == 'machine_product' ? record['product'] : null);
      if (relationName == 'machine_product' &&
          relatedValue is Map &&
          relatedValue['product'] is Map) {
        flattened[entry.key] = _RelatedRecords(
          _label('product'),
          [Map<String, dynamic>.from(relatedValue['product'] as Map)],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (entry.key == 'product' &&
          record['machine_product'] is Map &&
          (record['machine_product'] as Map)['product'] is Map) {
        flattened[entry.key] = _RelatedRecords(
          _label('product'),
          [
            Map<String, dynamic>.from(
              (record['machine_product'] as Map)['product'] as Map,
            ),
          ],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (relationName != null && relatedValue is Map) {
        flattened[entry.key] = _RelatedRecords(
          _label(relationName),
          [Map<String, dynamic>.from(relatedValue)],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (relationName == 'person' && record['__person_display'] != null) {
        flattened[entry.key] = record['__person_display'].toString();
        continue;
      }
      if (relationName == 'machine' &&
          machineRecord != null &&
          record[entry.key] == machineRecord!['id']) {
        flattened[entry.key] = _RelatedRecords(
          _label(relationName!),
          [machineRecord!],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (entry.key == 'machine' &&
          machineRecord != null &&
          record[entry.key] == machineRecord!['id']) {
        flattened[entry.key] = _RelatedRecords(
          _label('machine'),
          [machineRecord!],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (hasLinkedSensor && entry.key == 'machine_sensor') {
        flattened[entry.key] = _RelatedRecords(
          _label('sensor'),
          [Map<String, dynamic>.from(record['sensor'] as Map)],
          parentRecord: record,
          parentField: entry.key,
        );
        continue;
      }
      if (relationDisplays[entry.key] != null) {
        flattened[entry.key] = relationDisplays[entry.key].toString();
        continue;
      }
      if (!entry.key.startsWith('__') && !entry.key.endsWith('_id')) {
        final displayValues = record['__field_display'] is Map
            ? Map<String, dynamic>.from(record['__field_display'] as Map)
            : const <String, dynamic>{};
        final choices = record['__field_choices'] is Map
            ? Map<String, dynamic>.from(record['__field_choices'] as Map)
            : const <String, dynamic>{};
        addValue(
          entry.key,
          displayValues.containsKey(entry.key)
              ? displayValues[entry.key]
              : entry.value,
          choices: choices,
          fieldName: entry.key,
        );
      }
    }
    return flattened;
  }

  List<Map<String, dynamic>>? _decodeRecordList(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List ||
          decoded.isEmpty ||
          decoded.any((item) => item is! Map)) {
        return null;
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } on FormatException {
      return null;
    }
  }

  String _displayValue(dynamic value) {
    if (value is Map) {
      return value.entries
          .where((entry) => !entry.key.toString().startsWith('__'))
          .map(
            (entry) => '${_label(entry.key.toString())}: ${entry.value ?? '—'}',
          )
          .join(' · ');
    }
    return value?.toString() ?? '—';
  }

  List<Map<String, dynamic>> _editableFieldsForRecord(
    Map<String, dynamic> record,
  ) {
    return (record['__editable_fields'] as List? ?? const [])
        .whereType<Map>()
        .map((field) => Map<String, dynamic>.from(field))
        .where((field) => field['editable'] != false)
        .toList();
  }

  Future<void> _editRecord(
    BuildContext context,
    String label,
    Map<String, dynamic> record,
  ) async {
    final resource = record['__resource'] as String;
    final recordId = (record['id'] as num).toInt();
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AdminRecordEditDialog(
        title: _label(label),
        machineSerial: machineSerial,
        resource: resource,
        recordId: recordId,
        record: record,
        labelFor: _label,
        editableFields: _editableFieldsForRecord(record),
      ),
    );
    if (values == null || !context.mounted) return;
    try {
      await onUpdateRecord(resource, recordId, values);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تغییرات ذخیره شد')));
    } on DioException catch (error) {
      if (!context.mounted) return;
      final response = error.response?.data;
      final message = response is Map
          ? response.entries
                .map((entry) => '${entry.key}: ${entry.value}')
                .join(' | ')
          : 'ذخیره تغییرات ناموفق بود';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _label(String key) {
    if (key.contains(' · ')) {
      return key.split(' · ').map(_label).join(' · ');
    }
    const labels = {
      'machine': 'دستگاه',
      'version': 'نسخه دستگاه',
      'counts': 'تعداد رکوردها',
      'consumables': 'مواد مصرفی',
      'products': 'محصولات دستگاه',
      'consumable_changes': 'تاریخچه تغییر موجودی',
      'price_history': 'تاریخچه قیمت',
      'contracts': 'قراردادها',
      'items': 'سوابق',
      'sensors': 'سنسورها',
      'readings': 'داده‌های سنسور',
      'installed': 'قطعات نصب‌شده',
      'version_components': 'قطعات نسخه',
      'version_products': 'محصولات نسخه',
      'machine_discounts': 'تخفیف دستگاه',
      'product_discounts': 'تخفیف محصولات',
      'servicers': 'تکنسین‌های سرویس',
      'qr_codes': 'کدهای QR',
      'error': 'شرح خطا',
      'discount': 'تخفیف',
      'product': 'محصول',
      'person': 'مشخصات فرد',
      'partner': 'شریک تجاری',
      'city': 'شهر',
      'province': 'استان',
      'pos_account': 'حساب تسویه',
      'deposit': 'ودیعه',
      'service_receipt': 'رسید خدمات',
      'receipt_transaction': 'تراکنش رسید',
      'transactions': 'تراکنش‌های بانکی',
      'wallet_changes': 'تغییرات کیف پول',
      'discounts': 'تخفیف‌های اعمال‌شده',
      'has_more': 'موارد بیشتری وجود دارد',
      'total': 'تعداد کل',
      'offset': 'شروع صفحه',
      'limit': 'تعداد در صفحه',
      'machine_consumable': 'موجودی دستگاه',
      'consumable': 'ماده مصرفی',
      'machine_consumable_change': 'تغییر موجودی',
      'machine_product': 'محصول دستگاه',
      'machine_product_log': 'تغییر قیمت',
      'product_consumable': 'فرمول مصرف محصول',
      'machine_sensor': 'اتصال سنسور',
      'sensor_data': 'داده سنسور',
      'machine_component': 'قطعه نصب‌شده',
      'machine_discount': 'تخفیف دستگاه',
      'product_discount': 'تخفیف محصول',
      'contract_machine_product': 'سهم محصول در قرارداد',
      'assigned_quota': 'سهمیه شهر',
      'assigned_quota_log': 'تاریخچه سهمیه',
      'bank_account': 'حساب بانکی',
      'machine_receipt': 'رسید خرید',
      'machine_receipt_discount': 'تخفیف رسید',
      'wallet_change': 'تغییر کیف پول',
      'user_wallet': 'کیف پول',
      'user_discount': 'تخفیف کاربر',
      'machine_qr_code': 'کد QR',
      'error_log': 'گزارش خطا',
      'error_dictionary': 'تعریف خطا',
      'machine_version_component': 'قطعه نسخه',
      'machine_version_product': 'محصول نسخه',
      'transaction': 'تراکنش',
      'servicer_assignment': 'تخصیص سرویس‌کار',
      'servicer': 'سرویس‌کار',
      'user': 'کاربر',
      'subscription': 'اشتراک',
      'check': 'چک',
      'id': 'شناسه',
      'name': 'نام',
      'serial': 'سریال',
      'status': 'وضعیت',
      'amount': 'مقدار',
      'computed_amount': 'موجودی محاسبه‌شده',
      'creation_date': 'تاریخ ایجاد',
      'last_update': 'آخرین بروزرسانی',
      'contract': 'شناسه قرارداد',
      'user_id': 'شناسه کاربر',
      'person_id': 'نام / شماره تماس',
      'description': 'توضیحات',
      'code': 'کد',
      'serial_number': 'شماره سریال',
      'start_date': 'تاریخ شروع',
      'end_date': 'تاریخ پایان',
      'date': 'تاریخ',
      'price': 'قیمت',
      'count': 'تعداد',
      'is_active': 'فعال',
      'active': 'وضعیت فعالیت',
      'enabled': 'فعال',
      'discount_amount': 'مبلغ تخفیف',
      'percentage': 'درصد',
      'error_code': 'کد خطا',
      'sensor_serial': 'سریال سنسور',
      'sensor_name': 'نام سنسور',
      'last_value': 'آخرین مقدار',
      'last_received': 'آخرین دریافت',
      'component_description': 'شرح قطعه',
      'critical_error_code': 'کد خطای بحرانی',
      'receipt_serial': 'سریال رسید',
      'stored_amount': 'موجودی ثبت‌شده',
      'machine_sensor_id': 'شناسه اتصال سنسور',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }
}

class _AdminRecordsTable extends StatefulWidget {
  const _AdminRecordsTable({
    required this.title,
    required this.records,
    required this.flattenRecord,
    required this.labelFor,
    required this.onEdit,
    required this.onLoadMore,
    required this.onRefresh,
    required this.hasMore,
    required this.isLoading,
    this.selectionMode = false,
    this.selectedRecordIds = const {},
    this.onToggleRecord,
    this.total,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final dynamic total;
  final Map<String, dynamic> Function(Map<String, dynamic>) flattenRecord;
  final String Function(String) labelFor;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final VoidCallback onLoadMore;
  final VoidCallback onRefresh;
  final bool hasMore;
  final bool isLoading;
  final bool selectionMode;
  final Set<int> selectedRecordIds;
  final ValueChanged<int>? onToggleRecord;

  @override
  State<_AdminRecordsTable> createState() => _AdminRecordsTableState();
}

class _AdminRecordsTableState extends State<_AdminRecordsTable> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalController = ScrollController();
  final Set<String> _hiddenColumns = {};
  String? _sortField;
  String? _statusFilter;
  bool _ascending = true;

  bool _canEdit(Map<String, dynamic> record) =>
      record['__resource'] is String && record['id'] is num;

  String _display(dynamic value) {
    if (value is! _RelatedRecords) return value?.toString() ?? '—';
    if (value.records.length == 1) {
      final record = value.records.single;
      final display = _personAwareRecordDisplay(record);
      if (display.isNotEmpty) return display;
      for (final field in const ['name', 'serial', 'serial_number']) {
        final label = record[field]?.toString().trim();
        if (label != null && label.isNotEmpty) return label;
      }
    }
    return '${value.records.length} رکورد مرتبط';
  }

  String _personAwareRecordDisplay(Map<String, dynamic> record) {
    final person = record['person'];
    if (person is Map) {
      final fullName = [person['first_name'], person['last_name']]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .join(' ');
      final phone = person['phone_number']?.toString().trim() ?? '';
      final display = [
        fullName,
        phone,
      ].where((part) => part.trim().isNotEmpty).join(' · ');
      if (display.isNotEmpty) return display;
    }
    for (final key in const ['__person_display', '__display_name']) {
      final value = record[key]?.toString().trim();
      if (value != null &&
          value.isNotEmpty &&
          value != '—' &&
          value != record['id']?.toString()) {
        return value;
      }
    }
    return '';
  }

  List<String> get _allColumns {
    final fields = <String>{};
    for (final record in widget.records) {
      fields.addAll(widget.flattenRecord(record).keys);
    }
    fields.remove('sensor');
    return fields.toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  int _compare(String left, String right) {
    final leftNumber = num.tryParse(left);
    final rightNumber = num.tryParse(right);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    final leftDate = DateTime.tryParse(left);
    final rightDate = DateTime.tryParse(right);
    if (leftDate != null && rightDate != null) {
      return leftDate.compareTo(rightDate);
    }
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  List<Map<String, dynamic>> get _visibleRecords {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.records.where((record) {
      final values = widget.flattenRecord(record);
      if (_statusFilter != null && values['status'] != _statusFilter) {
        return false;
      }
      return query.isEmpty ||
          values.values.any(
            (value) => _display(value).toLowerCase().contains(query),
          );
    }).toList();
    final sortField = _sortField;
    if (sortField != null) {
      filtered.sort((left, right) {
        final comparison = _compare(
          _display(widget.flattenRecord(left)[sortField]),
          _display(widget.flattenRecord(right)[sortField]),
        );
        return _ascending ? comparison : -comparison;
      });
    }
    return filtered;
  }

  Future<void> _showColumnSettings(List<String> columns) async {
    // Ensure 'sensor' is not hidden when showing column settings
    _hiddenColumns.remove('sensor');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ستون‌های قابل نمایش'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final column in columns)
                  CheckboxListTile(
                    dense: true,
                    title: Text(widget.labelFor(column)),
                    value: !_hiddenColumns.contains(column),
                    onChanged: (visible) {
                      setState(() {
                        if (visible == true) {
                          _hiddenColumns.remove(column);
                        } else {
                          _hiddenColumns.add(column);
                        }
                      });
                      setDialogState(() {});
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('بستن'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRelatedRecords(_RelatedRecords related) async {
    final parentRow = widget.flattenRecord(related.parentRecord);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          related.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'بستن',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 36,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 48,
                        horizontalMargin: 10,
                        columnSpacing: 16,
                        border: TableBorder.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        headingTextStyle: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        dataTextStyle: Theme.of(context).textTheme.bodySmall,
                        columns: [
                          for (final field in parentRow.keys)
                            DataColumn(
                              label: Center(
                                child: Text(widget.labelFor(field)),
                              ),
                            ),
                        ],
                        rows: [
                          DataRow(
                            cells: [
                              for (final field in parentRow.keys)
                                DataCell(
                                  Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 40,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: field == related.parentField
                                        ? BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            border: Border.all(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                              width: 2,
                                            ),
                                          )
                                        : null,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      field == related.parentField
                                          ? '${_display(parentRow[field])}  ←'
                                          : _display(parentRow[field]),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _AdminRecordsTable(
                        title: related.title,
                        records: related.records,
                        flattenRecord: widget.flattenRecord,
                        labelFor: widget.labelFor,
                        onEdit: widget.onEdit,
                        onLoadMore: () {},
                        onRefresh: widget.onRefresh,
                        hasMore: false,
                        isLoading: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = _allColumns;
    final visibleColumns = columns
        .where((column) => !_hiddenColumns.contains(column))
        .toList();
    final sortColumnIndex = _sortField == null
        ? null
        : visibleColumns.indexOf(_sortField!);
    final records = _visibleRecords;
    final hasEditAction = !widget.selectionMode && widget.records.any(_canEdit);
    final statusValues = widget.records
        .map((record) => widget.flattenRecord(record)['status'])
        .whereType<String>()
        .where((status) => status != '—')
        .toSet()
        .toList();
    if (_sortField == null && columns.isNotEmpty) _sortField = columns.first;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'بروزرسانی ${widget.title}',
                  onPressed: widget.isLoading ? null : widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
                Text(
                  '${records.length}${widget.total is num ? ' · ${widget.total} کل' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  tooltip: 'تنظیم ستون‌ها',
                  onPressed: columns.isEmpty
                      ? null
                      : () => _showColumnSettings(columns),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'جستجو در ${widget.title}',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'پاک کردن جستجو',
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_sortField != null)
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _sortField,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'مرتب‌سازی بر اساس',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final column in columns)
                          DropdownMenuItem(
                            value: column,
                            child: Text(widget.labelFor(column)),
                          ),
                      ],
                      onChanged: (field) => setState(() => _sortField = field),
                    ),
                  ),
                IconButton(
                  tooltip: _ascending ? 'مرتب‌سازی نزولی' : 'مرتب‌سازی صعودی',
                  onPressed: () => setState(() => _ascending = !_ascending),
                  icon: Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  ),
                ),
                if (statusValues.isNotEmpty) ...[
                  FilterChip(
                    label: const Text('همه وضعیت‌ها'),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                  for (final status in statusValues)
                    FilterChip(
                      label: Text(status),
                      selected: _statusFilter == status,
                      onSelected: (_) => setState(() => _statusFilter = status),
                    ),
                ],
              ],
            ),
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('موردی برای نمایش وجود ندارد'),
            )
          else
            Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 36,
                  horizontalMargin: 10,
                  columnSpacing: 16,
                  dividerThickness: 1,
                  border: TableBorder(
                    horizontalInside: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    verticalInside: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  headingTextStyle: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  dataTextStyle: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                  ),
                  sortColumnIndex:
                      sortColumnIndex != null && sortColumnIndex >= 0
                      ? sortColumnIndex
                      : null,
                  sortAscending: _ascending,
                  headingRowColor: WidgetStatePropertyAll(
                    theme.colorScheme.surfaceContainerHighest,
                  ),
                  columns: [
                    if (widget.selectionMode)
                      const DataColumn(
                        label: SizedBox(
                          width: 44,
                          child: Center(child: Text('انتخاب')),
                        ),
                      ),
                    for (final field in visibleColumns)
                      DataColumn(
                        label: Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 124),
                            child: Center(child: Text(widget.labelFor(field))),
                          ),
                        ),
                        onSort: (index, ascending) => setState(() {
                          _sortField = field;
                          _ascending = ascending;
                        }),
                      ),
                    if (hasEditAction)
                      const DataColumn(
                        label: SizedBox(
                          width: 56,
                          child: Center(child: Text('عملیات')),
                        ),
                      ),
                  ],
                  rows: [
                    for (final record in records)
                      DataRow(
                        cells: [
                          if (widget.selectionMode)
                            DataCell(
                              Checkbox(
                                value: widget.selectedRecordIds.contains(
                                  (record['id'] as num?)?.toInt(),
                                ),
                                onChanged: (checked) {
                                  final id = (record['id'] as num).toInt();
                                  if (widget.onToggleRecord != null) {
                                    widget.onToggleRecord!(id);
                                  }
                                },
                              ),
                            ),
                          for (final field in visibleColumns)
                            DataCell(
                              SizedBox(
                                height: 36,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 280,
                                    ),
                                    child: _buildCell(
                                      widget.flattenRecord(record)[field],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (hasEditAction)
                            DataCell(
                              _canEdit(record)
                                  ? IconButton(
                                      tooltip: 'ویرایش ${widget.title}',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 32,
                                            height: 32,
                                          ),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () => widget.onEdit(record),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text('${records.length} مورد نمایش داده شده'),
            ),
          ),
          if (widget.hasMore)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: widget.isLoading ? null : widget.onLoadMore,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('بارگذاری موارد بیشتر'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCell(dynamic value) {
    if (value is _RelatedRecords) {
      return TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: () => _showRelatedRecords(value),
        icon: const Icon(Icons.open_in_new, size: 13),
        label: Text(
          value.records.length == 1 && _display(value) != '1 رکورد مرتبط'
              ? _display(value)
              : 'نمایش (${value.records.length})',
        ),
      );
    }
    return Center(
      child: Text(_display(value), textAlign: TextAlign.center, maxLines: 4),
    );
  }
}

class _RelatedRecords {
  const _RelatedRecords(
    this.title,
    this.records, {
    required this.parentRecord,
    required this.parentField,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final Map<String, dynamic> parentRecord;
  final String parentField;
}

class _AdminRecordEditDialog extends StatefulWidget {
  const _AdminRecordEditDialog({
    required this.title,
    required this.machineSerial,
    required this.resource,
    required this.recordId,
    required this.record,
    required this.labelFor,
    required this.editableFields,
  });

  final String title;
  final String machineSerial;
  final String resource;
  final int recordId;
  final Map<String, dynamic> record;
  final String Function(String) labelFor;
  final List<Map<String, dynamic>> editableFields;

  @override
  State<_AdminRecordEditDialog> createState() => _AdminRecordEditDialogState();
}

class _AdminRecordEditDialogState extends State<_AdminRecordEditDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _booleanValues = {};
  final Map<String, dynamic> _selectedValues = {};
  final Map<String, String> _relationLabels = {};
  final Map<String, List<Map<String, dynamic>>> _selectedRecords = {};
  final Set<String> _loadingRelations = {};
  String? _validationError;

  List<Map<String, dynamic>> get _fields => widget.editableFields;

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      final name = field['name'] as String;
      final rawValue = widget.record[name];
      final value = field['relation'] == true
          ? widget.record['${name}_id'] ??
                (rawValue is Map ? rawValue['id'] : rawValue)
          : rawValue ?? widget.record['${name}_id'];
      if (field['type'] == 'BooleanField') {
        _booleanValues[name] = value == true;
      } else if (field['relation'] == true ||
          (field['choices'] as List? ?? const []).isNotEmpty) {
        if (field['multiple'] == true) {
          _selectedValues[name] = value is List
              ? value
                    .map((item) => item is Map ? item['id'] : item)
                    .whereType<num>()
                    .map((id) => id.toInt())
                    .toList()
              : <int>[];
        } else {
          _selectedValues[name] = value is Map ? value['id'] : value;
        }
      } else {
        _controllers[name] = TextEditingController(
          text: value?.toString() ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _collectValues() {
    final values = <String, dynamic>{};
    for (final field in _fields) {
      final name = field['name'] as String;
      final type = field['type'] as String;
      if (type == 'BooleanField') {
        values[name] = _booleanValues[name] ?? false;
        continue;
      }
      if (field['relation'] == true ||
          (field['choices'] as List? ?? const []).isNotEmpty) {
        final selected = _selectedValues[name];
        if (field['multiple'] == true) {
          values[name] = List<dynamic>.from(selected as List? ?? const []);
        } else if (selected == null && field['nullable'] != true) {
          setState(
            () => _validationError =
                'مقدار ${widget.labelFor(name)} را انتخاب کنید',
          );
          return null;
        } else {
          values[name] = selected;
        }
        continue;
      }
      final text = _controllers[name]!.text.trim();
      if (text.isEmpty) {
        values[name] = field['nullable'] == true ? null : '';
      } else if (const {
        'AutoField',
        'BigAutoField',
        'BigIntegerField',
        'IntegerField',
        'PositiveBigIntegerField',
        'PositiveIntegerField',
        'SmallIntegerField',
        'PositiveSmallIntegerField',
      }.contains(type)) {
        final parsed = int.tryParse(text);
        if (parsed == null) {
          setState(
            () => _validationError =
                'مقدار ${widget.labelFor(name)} باید عدد صحیح باشد',
          );
          return null;
        }
        values[name] = parsed;
      } else if (type == 'FloatField') {
        final parsed = double.tryParse(text);
        if (parsed == null) {
          setState(
            () =>
                _validationError = 'مقدار ${widget.labelFor(name)} معتبر نیست',
          );
          return null;
        }
        values[name] = parsed;
      } else {
        values[name] = text;
      }
    }
    return values;
  }

  String _relatedRecordsDisplay(List<Map<String, dynamic>> records) {
    if (records.length == 1) {
      final record = records.single;
      final person = record['person'];
      if (person is Map) {
        final fullName = [person['first_name'], person['last_name']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(' ');
        final phone = person['phone_number']?.toString().trim() ?? '';
        final personText = [
          fullName,
          phone,
        ].where((part) => part.trim().isNotEmpty).join(' · ');
        if (personText.isNotEmpty) return personText;
      }
      final personDisplay = record['__person_display']?.toString().trim();
      if (personDisplay != null && personDisplay.isNotEmpty) {
        return personDisplay;
      }
      for (final field in const ['name', 'serial', 'serial_number']) {
        final value = record[field]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      for (final key in const ['__display_name']) {
        final display = record[key]?.toString().trim();
        if (display != null &&
            display.isNotEmpty &&
            display != '—' &&
            display != record['id']?.toString()) {
          return display;
        }
      }
    }
    return '${records.length} رکورد مرتبط';
  }

  String _personAwareRecordDisplay(Map<String, dynamic> record) {
    final person = record['person'];
    if (person is Map) {
      final name = [person['first_name'], person['last_name']]
          .where((part) => part != null && part.toString().trim().isNotEmpty)
          .join(' ');
      final phone = person['phone_number']?.toString().trim() ?? '';
      final display = [
        name,
        phone,
      ].where((part) => part.trim().isNotEmpty).join(' · ');
      if (display.isNotEmpty) return display;
    }
    for (final key in const ['__person_display', '__display_name']) {
      final value = record[key]?.toString().trim();
      if (value != null && value.isNotEmpty && value != '—') return value;
    }
    return '';
  }

  dynamic _relationDisplayFor(
    Map<String, dynamic> record,
    String key,
    dynamic value,
  ) {
    if (value is Map || value is List) return value;
    final displays = record['__relation_display'];
    if (displays is Map && displays[key] != null) {
      return displays[key].toString();
    }
    return value;
  }

  Future<void> _selectRelation(Map<String, dynamic> field) async {
    final name = field['name'] as String;
    if (_loadingRelations.contains(name)) return;
    final current = _selectedValues[name];
    setState(() => _loadingRelations.add(name));
    try {
      final response = await ProductService.getAdminMachineRelationOptions(
        widget.machineSerial,
        resource: widget.resource,
        recordId: widget.recordId,
        field: name,
        limit: 100,
      );
      if (!mounted) return;
      setState(() => _loadingRelations.remove(name));
      final data = Map<String, dynamic>.from(response.data);
      final records = <Map<String, dynamic>>[
        ...(data['items'] as List? ?? const []).whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
      ];
      final currentRecords = (data['current_records'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      var offset = records.length;
      var loadingMore = false;
      if (!mounted) return;
      final relationMultiple = data['multiple'] == true;
      final relationMode = data['relation_mode']?.toString();
      final currentIds = (data['current_ids'] as List? ?? const [])
          .whereType<num>()
          .map((id) => id.toInt())
          .toList();
      final selection = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          final multiple = relationMultiple;
          final selectedIds = <int>{
            ...currentIds,
            if (currentIds.isEmpty && multiple && current is List)
              ...current.whereType<num>().map((value) => value.toInt()),
            if (currentIds.isEmpty && !multiple && current is num)
              current.toInt(),
          };
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Directionality(
                textDirection: TextDirection.rtl,
                child: Dialog.fullscreen(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'انتخاب ${widget.labelFor(name)}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ),
                              IconButton(
                                tooltip: 'بستن',
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: _AdminRecordsTable(
                                title: widget.labelFor(
                                  field['related_resource']?.toString() ?? name,
                                ),
                                records: records,
                                total: data['total'],
                                flattenRecord: (record) => {
                                  if (_personAwareRecordDisplay(
                                    record,
                                  ).isNotEmpty)
                                    'person_display': _personAwareRecordDisplay(
                                      record,
                                    ),
                                  for (final entry in record.entries)
                                    if (!entry.key.startsWith('__') &&
                                        entry.key != 'person')
                                      entry.key:
                                          (record['__field_display']
                                                  as Map?)?[entry.key] ??
                                              _relationDisplayFor(
                                                record,
                                                entry.key,
                                                entry.value,
                                              ),
                                },
                                labelFor: widget.labelFor,
                                onEdit: (_) {},
                                onLoadMore: () async {
                                  if (loadingMore || data['has_more'] != true) {
                                    return;
                                  }
                                  setDialogState(() => loadingMore = true);
                                  try {
                                    final nextResponse =
                                        await ProductService.getAdminMachineRelationOptions(
                                          widget.machineSerial,
                                          resource: widget.resource,
                                          recordId: widget.recordId,
                                          field: name,
                                          offset: offset,
                                        );
                                    final nextPage = Map<String, dynamic>.from(
                                      nextResponse.data,
                                    );
                                    records.addAll(
                                      (nextPage['items'] as List? ?? const [])
                                          .whereType<Map>()
                                          .map(
                                            (item) =>
                                                Map<String, dynamic>.from(item),
                                          ),
                                    );
                                    offset = records.length;
                                    data['has_more'] = nextPage['has_more'];
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'بارگذاری موارد بیشتر ناموفق بود',
                                          ),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      setDialogState(() => loadingMore = false);
                                    }
                                  }
                                },
                                onRefresh: () {},
                                hasMore: data['has_more'] == true,
                                isLoading: loadingMore,
                                selectionMode: true,
                                selectedRecordIds: selectedIds,
                                onToggleRecord: (id) => setDialogState(() {
                                  if (multiple) {
                                    if (!selectedIds.add(id)) {
                                      selectedIds.remove(id);
                                    }
                                  } else {
                                    if (selectedIds.contains(id)) {
                                      selectedIds.clear();
                                    } else {
                                      selectedIds
                                        ..clear()
                                        ..add(id);
                                    }
                                  }
                                }),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Text(
                                  '${data['total'] ?? records.length} رکورد واجد شرایط · ${selectedIds.length} انتخاب‌شده',
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialogContext),
                                  child: const Text('لغو'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(dialogContext, {
                                        'mode': relationMode,
                                        'ids': selectedIds.toList(),
                                      }),
                                  child: const Text('تأیید انتخاب'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      if (selection != null && mounted) {
        final selectedIds = (selection['ids'] as List? ?? const [])
            .whereType<num>()
            .map((id) => id.toInt())
            .toList();
        final allKnownRecords = [...currentRecords, ...records];
        final selectedRecords = allKnownRecords
            .where(
              (option) => selectedIds.contains((option['id'] as num?)?.toInt()),
            )
            .toList();
        setState(() {
          _selectedValues[name] = relationMultiple
              ? selectedIds
              : selectedIds.isEmpty
              ? null
              : selectedIds.first;
          _selectedRecords[name] = selectedRecords;
          _relationLabels[name] = _relatedRecordsDisplay(selectedRecords);
          _validationError = null;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingRelations.remove(name));
      final detail = error is DioException ? error.response?.data : null;
      final message = detail is Map
          ? detail.values.join(' ')
          : 'بارگذاری گزینه‌های مرتبط ناموفق بود';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _selectChoice(Map<String, dynamic> field) async {
    final name = field['name'] as String;
    final choices = (field['choices'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('انتخاب ${widget.labelFor(name)}'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (field['nullable'] == true)
                ListTile(
                  title: const Text('—'),
                  selected: _selectedValues[name] == null,
                  onTap: () => Navigator.pop(dialogContext, {'value': null}),
                ),
              for (final choice in choices)
                ListTile(
                  title: Text(choice['label'].toString()),
                  selected:
                      choice['value'].toString() ==
                      _selectedValues[name]?.toString(),
                  onTap: () =>
                      Navigator.pop(dialogContext, {'value': choice['value']}),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedValues[name] = result['value'];
        _validationError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('ویرایش ${widget.title}'),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final field in _fields)
                if (field['type'] == 'BooleanField')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.labelFor(field['name'] as String)),
                    value: _booleanValues[field['name']] ?? false,
                    onChanged: (value) => setState(
                      () => _booleanValues[field['name'] as String] = value,
                    ),
                  )
                else if (field['relation'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: _loadingRelations.contains(field['name'])
                          ? null
                          : () => _selectRelation(field),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: widget.labelFor(field['name'] as String),
                          border: const OutlineInputBorder(),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (field['nullable'] == true &&
                                  field['multiple'] != true &&
                                  _selectedValues[field['name']] != null)
                                IconButton(
                                  tooltip: 'پاک کردن انتخاب',
                                  onPressed: () => setState(
                                    () =>
                                        _selectedValues[field['name']
                                                as String] =
                                            null,
                                  ),
                                  icon: const Icon(Icons.clear),
                                ),
                              if (_loadingRelations.contains(field['name']))
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                        child: Text(_selectedRelationLabel(field)),
                      ),
                    ),
                  )
                else if ((field['choices'] as List? ?? const []).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () => _selectChoice(field),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: widget.labelFor(field['name'] as String),
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(_selectedChoiceLabel(field)),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _controllers[field['name']],
                      keyboardType:
                          const {
                            'AutoField',
                            'BigAutoField',
                            'BigIntegerField',
                            'IntegerField',
                            'PositiveBigIntegerField',
                            'PositiveIntegerField',
                            'SmallIntegerField',
                            'PositiveSmallIntegerField',
                            'DecimalField',
                            'FloatField',
                          }.contains(field['type'])
                          ? const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            )
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: widget.labelFor(field['name'] as String),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              if (_validationError != null)
                Text(
                  _validationError!,
                  style: TextStyle(color: colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('لغو'),
        ),
        FilledButton.icon(
          onPressed: () {
            final values = _collectValues();
            if (values != null) Navigator.pop(context, values);
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('ذخیره'),
        ),
      ],
    );
  }

  String _selectedRelationLabel(Map<String, dynamic> field) {
    final value = _selectedValues[field['name']];
    if (field['multiple'] == true ||
        field['relation_mode'] == 'many_to_many_through') {
      final ids = value is List ? value : const [];
      if (ids.isEmpty) return 'برای انتخاب رکوردها لمس کنید';
      final selectedLabel = _relationLabels[field['name']];
      return selectedLabel != null && selectedLabel.isNotEmpty
          ? selectedLabel
          : '${ids.length} رکورد مرتبط';
    }
    if (value == null) return 'برای انتخاب رکورد لمس کنید';
    final selectedLabel = _relationLabels[field['name']];
    if (selectedLabel != null && selectedLabel.isNotEmpty) return selectedLabel;
    final name = field['name'] as String;
    final cachedRecords = _selectedRecords[name];
    if (cachedRecords != null && cachedRecords.isNotEmpty) {
      return _relatedRecordsDisplay(cachedRecords);
    }
    final rawId = value is num ? value.toInt() : int.tryParse(value.toString());
    final related = widget.record[name];
    if (rawId != null && related is List) {
      final selectedRecords = related
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['id'] as num?)?.toInt() == rawId)
          .toList();
      if (selectedRecords.isNotEmpty) {
        return _relatedRecordsDisplay(selectedRecords);
      }
    }
    final nested = widget.record[name];
    if (nested is Map && nested['id']?.toString() == value.toString()) {
      return _relatedRecordsDisplay([Map<String, dynamic>.from(nested)]);
    }
    final relationDisplays = widget.record['__relation_display'];
    if (relationDisplays is Map && relationDisplays[name] != null) {
      return relationDisplays[name].toString();
    }
    return 'شناسه $value';
  }

  String _selectedChoiceLabel(Map<String, dynamic> field) {
    final value = _selectedValues[field['name']];
    final storedDisplay = widget.record['__field_display'];
    if (storedDisplay is Map && storedDisplay[field['name']] != null) {
      final storedValue = widget.record[field['name']];
      if (storedValue?.toString() == value?.toString()) {
        return storedDisplay[field['name']].toString();
      }
    }
    for (final choice
        in (field['choices'] as List? ?? const []).whereType<Map>()) {
      if (choice['value'].toString() == value?.toString()) {
        return choice['label'].toString();
      }
    }
    return value == null ? 'برای انتخاب گزینه لمس کنید' : value.toString();
  }
}
