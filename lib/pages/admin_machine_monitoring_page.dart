import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_production_test/pages/admin_machine_details_page.dart';
import 'package:flutter_production_test/services/admin_auth_session.dart';
import 'package:flutter_production_test/services/product_service.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class AdminMachineMonitoringPage extends StatefulWidget {
  const AdminMachineMonitoringPage({super.key});

  static const String routePath = '/admin/machines';

  @override
  State<AdminMachineMonitoringPage> createState() =>
      _AdminMachineMonitoringPageState();
}

class _AdminMachineMonitoringPageState
    extends State<AdminMachineMonitoringPage> {
  static const List<(String, String)> _sortOptions = [
    ('id', 'شناسه'),
    ('name', 'نام دستگاه'),
    ('serial', 'سریال'),
    ('model', 'مدل'),
    ('manufacturer', 'سازنده'),
    ('location', 'مکان'),
    ('status', 'وضعیت'),
    ('version', 'نسخه'),
    ('standby_time', 'آماده‌باش'),
    ('cup_weight', 'وزن لیوان'),
    ('boiler_temp_threshold', 'آستانه بویلر'),
    ('creation_date', 'تاریخ ایجاد'),
  ];

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ScrollController _tableHorizontalController = ScrollController();
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _isLoggingIn = false;
  String? _loadError;
  String? _loginError;
  String _sortField = 'serial';
  bool _sortAscending = true;
  int? _statusFilter;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshView);
    _isAuthenticated = AdminAuthSession.isAuthenticated;
    if (_isAuthenticated) _loadMachines();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _tableHorizontalController.dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMachines() async {
    if (!AdminAuthSession.isAuthenticated) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ProductService.getAdminMachineList();
      final machines = _parseMachines(response.data);
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _isLoading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 401) AdminAuthSession.clear();
      setState(() {
        _isLoading = false;
        _isAuthenticated = AdminAuthSession.isAuthenticated;
        _loginError = error.response?.statusCode == 401
            ? 'نشست ورود منقضی شد؛ دوباره وارد شوید'
            : null;
        _loadError = _isAuthenticated
            ? 'خطا در دریافت اطلاعات دستگاه‌ها از سرور'
            : null;
      });
    }
  }

  List<Map<String, dynamic>> _parseMachines(dynamic data) {
    if (data is! List) return [];
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<void> _signIn() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'نام کاربری و گذرواژه را وارد کنید');
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });
    try {
      final response = await ProductService.authenticateAdmin(
        username,
        password,
      );
      if (!mounted) return;
      setState(() {
        _machines = _parseMachines(response.data);
        _isAuthenticated = true;
        _isLoggingIn = false;
        _isLoading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoggingIn = false;
        _loginError = switch (error.response?.statusCode) {
          401 => 'نام کاربری یا گذرواژه نادرست است',
          403 => 'این حساب دسترسی مدیریتی ندارد',
          _ => 'اتصال به سرور یا دریافت فهرست دستگاه‌ها ناموفق بود',
        };
      });
    }
  }

  void _signOut() {
    AdminAuthSession.clear();
    _passwordController.clear();
    setState(() {
      _machines = [];
      _isAuthenticated = false;
      _isLoading = false;
      _loadError = null;
      _loginError = null;
    });
  }

  List<Map<String, dynamic>> get _visibleMachines {
    final query = _searchController.text.trim().toLowerCase();
    final machines = _machines.where((machine) {
      if (_statusFilter != null && machine['status'] != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        'serial',
        'name',
        'model',
        'manufacturer',
        'location',
        'version',
      ].any(
        (key) =>
            machine[key]?.toString().toLowerCase().contains(query) ?? false,
      );
    }).toList();

    machines.sort((left, right) {
      final leftValue = left[_sortField];
      final rightValue = right[_sortField];
      int result;
      if (leftValue is num && rightValue is num) {
        result = leftValue.compareTo(rightValue);
      } else {
        final leftDate = DateTime.tryParse(leftValue?.toString() ?? '');
        final rightDate = DateTime.tryParse(rightValue?.toString() ?? '');
        if (leftDate != null && rightDate != null) {
          result = leftDate.compareTo(rightDate);
        } else {
          result = (leftValue?.toString() ?? '').toLowerCase().compareTo(
            (rightValue?.toString() ?? '').toLowerCase(),
          );
        }
      }
      return _sortAscending ? result : -result;
    });
    return machines;
  }

  void _sortBy(String field, int columnIndex, bool ascending) {
    setState(() {
      _sortField = field;
      _sortAscending = ascending;
    });
  }

  String _display(dynamic value) => value?.toString() ?? '—';

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null ? '—' : DateFormat('yyyy/MM/dd').format(date.toLocal());
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DataColumn _column(String label, String field, int index) => DataColumn(
    label: Text(label),
    onSort: (columnIndex, ascending) => _sortBy(field, columnIndex, ascending),
  );

  DataCell _textCell(dynamic value) => DataCell(Text(_display(value)));

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeCount = _machines
        .where((machine) => machine['status'] == 1)
        .length;
    final inactiveCount = _machines
        .where((machine) => machine['status'] == 2)
        .length;
    final machines = _visibleMachines;

    return Directionality(
      textDirection: .rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پنل مدیریت دستگاه‌ها'),
          actions: [
            if (_isAuthenticated) ...[
              IconButton(
                tooltip: 'بروزرسانی فهرست',
                onPressed: _isLoading ? null : _loadMachines,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'خروج از پنل',
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: _isAuthenticated
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final horizontalPadding = compact ? 12.0 : 24.0;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        compact ? 12 : 20,
                        horizontalPadding,
                        compact ? 12 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'پایش دستگاه‌ها',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          if (compact)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final metric in [
                                  _metric(
                                    'همه دستگاه‌ها',
                                    '${_machines.length}',
                                    Icons.memory,
                                    colorScheme.primary,
                                  ),
                                  _metric(
                                    'فعال',
                                    '$activeCount',
                                    Icons.check_circle_outline,
                                    Colors.green.shade700,
                                  ),
                                  _metric(
                                    'غیرفعال',
                                    '$inactiveCount',
                                    Icons.pause_circle_outline,
                                    colorScheme.error,
                                  ),
                                ])
                                  SizedBox(
                                    width:
                                        (constraints.maxWidth -
                                            2 * horizontalPadding -
                                            8) /
                                        2,
                                    child: metric,
                                  ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: _metric(
                                    'همه دستگاه‌ها',
                                    '${_machines.length}',
                                    Icons.memory,
                                    colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _metric(
                                    'فعال',
                                    '$activeCount',
                                    Icons.check_circle_outline,
                                    Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _metric(
                                    'غیرفعال',
                                    '$inactiveCount',
                                    Icons.pause_circle_outline,
                                    colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: compact
                                    ? constraints.maxWidth -
                                          2 * horizontalPadding
                                    : 360,
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'جستجوی نام، سریال، مدل یا مکان',
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _searchController.text.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'پاک کردن جستجو',
                                            onPressed: _searchController.clear,
                                            icon: const Icon(Icons.close),
                                          ),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              if (compact) ...[
                                SizedBox(
                                  width: 180,
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _sortField,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'مرتب‌سازی',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    items: [
                                      for (final option in _sortOptions)
                                        DropdownMenuItem(
                                          value: option.$1,
                                          child: Text(option.$2),
                                        ),
                                    ],
                                    onChanged: (field) {
                                      if (field != null) {
                                        setState(() => _sortField = field);
                                      }
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: _sortAscending
                                      ? 'مرتب‌سازی نزولی'
                                      : 'مرتب‌سازی صعودی',
                                  onPressed: () => setState(
                                    () => _sortAscending = !_sortAscending,
                                  ),
                                  icon: Icon(
                                    _sortAscending
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                  ),
                                ),
                              ],
                              FilterChip(
                                label: const Text('همه وضعیت‌ها'),
                                selected: _statusFilter == null,
                                onSelected: (_) =>
                                    setState(() => _statusFilter = null),
                              ),
                              FilterChip(
                                label: const Text('فعال'),
                                selected: _statusFilter == 1,
                                onSelected: (_) =>
                                    setState(() => _statusFilter = 1),
                              ),
                              FilterChip(
                                label: const Text('غیرفعال'),
                                selected: _statusFilter == 2,
                                onSelected: (_) =>
                                    setState(() => _statusFilter = 2),
                              ),
                              Text(
                                '${machines.length} دستگاه',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _isLoading && _machines.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _loadError != null
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.cloud_off_outlined,
                                          size: 40,
                                          color: colorScheme.error,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(_loadError!),
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          onPressed: _loadMachines,
                                          icon: const Icon(Icons.refresh),
                                          label: const Text('تلاش مجدد'),
                                        ),
                                      ],
                                    ),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      color: colorScheme.surface,
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: _isLoading
                                        ? const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        : machines.isEmpty
                                        ? Center(
                                            child: Text(
                                              'دستگاهی با این مشخصات یافت نشد',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyLarge,
                                            ),
                                          )
                                        : compact
                                        ? ListView.separated(
                                            padding: const EdgeInsets.all(8),
                                            itemCount: machines.length,
                                            separatorBuilder: (_, _) =>
                                                const SizedBox(height: 8),
                                            itemBuilder: (context, index) {
                                              final machine = machines[index];
                                              final status = machine['status'];
                                              final isActive = status == 1;
                                              return Card(
                                                margin: EdgeInsets.zero,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  _display(
                                                                    machine['name'],
                                                                  ),
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.titleMedium,
                                                                ),
                                                                const SizedBox(
                                                                  height: 2,
                                                                ),
                                                                Text(
                                                                  _display(
                                                                    machine['serial'],
                                                                  ),
                                                                  style: Theme.of(
                                                                    context,
                                                                  ).textTheme.bodySmall,
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          _StatusLabel(
                                                            label: isActive
                                                                ? 'فعال'
                                                                : status == 2
                                                                ? 'غیرفعال'
                                                                : 'نامشخص',
                                                            isActive: isActive,
                                                          ),
                                                          IconButton(
                                                            tooltip:
                                                                'مشاهده جزئیات دستگاه',
                                                            onPressed: () =>
                                                                context.push(
                                                                  '${AdminMachineDetailsPage.routePath}/${Uri.encodeComponent(machine['serial'].toString())}',
                                                                ),
                                                            icon: const Icon(
                                                              Icons.open_in_new,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const Divider(),
                                                      _mobileField(
                                                        'مدل',
                                                        machine['model'],
                                                      ),
                                                      _mobileField(
                                                        'سازنده',
                                                        machine['manufacturer'],
                                                      ),
                                                      _mobileField(
                                                        'مکان',
                                                        machine['location'],
                                                      ),
                                                      _mobileField(
                                                        'نسخه',
                                                        machine['version'],
                                                      ),
                                                      _mobileField(
                                                        'آماده‌باش (دقیقه)',
                                                        machine['standby_time'],
                                                      ),
                                                      _mobileField(
                                                        'وزن لیوان',
                                                        machine['cup_weight'],
                                                      ),
                                                      _mobileField(
                                                        'آستانه بویلر',
                                                        machine['boiler_temp_threshold'],
                                                      ),
                                                      _mobileField(
                                                        'تاریخ ایجاد',
                                                        _formatDate(
                                                          machine['creation_date'],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          )
                                        : SingleChildScrollView(
                                            child: Scrollbar(
                                              controller:
                                                  _tableHorizontalController,
                                              thumbVisibility: true,
                                              interactive: true,
                                              child: SingleChildScrollView(
                                                controller:
                                                    _tableHorizontalController,
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: DataTable(
                                                  sortColumnIndex: [
                                                    'id',
                                                    'name',
                                                    'serial',
                                                    'model',
                                                    'manufacturer',
                                                    'location',
                                                    'status',
                                                    'version',
                                                    'standby_time',
                                                    'cup_weight',
                                                    'boiler_temp_threshold',
                                                    'creation_date',
                                                  ].indexOf(_sortField),
                                                  sortAscending: _sortAscending,
                                                  headingRowColor:
                                                      WidgetStatePropertyAll(
                                                        colorScheme
                                                            .surfaceContainerHighest,
                                                      ),
                                                  columns: [
                                                    _column('شناسه', 'id', 0),
                                                    _column(
                                                      'نام دستگاه',
                                                      'name',
                                                      1,
                                                    ),
                                                    _column(
                                                      'سریال',
                                                      'serial',
                                                      2,
                                                    ),
                                                    _column('مدل', 'model', 3),
                                                    _column(
                                                      'سازنده',
                                                      'manufacturer',
                                                      4,
                                                    ),
                                                    _column(
                                                      'مکان',
                                                      'location',
                                                      5,
                                                    ),
                                                    _column(
                                                      'وضعیت',
                                                      'status',
                                                      6,
                                                    ),
                                                    _column(
                                                      'نسخه',
                                                      'version',
                                                      7,
                                                    ),
                                                    _column(
                                                      'آماده‌باش (دقیقه)',
                                                      'standby_time',
                                                      8,
                                                    ),
                                                    _column(
                                                      'وزن لیوان',
                                                      'cup_weight',
                                                      9,
                                                    ),
                                                    _column(
                                                      'آستانه بویلر',
                                                      'boiler_temp_threshold',
                                                      10,
                                                    ),
                                                    _column(
                                                      'تاریخ ایجاد',
                                                      'creation_date',
                                                      11,
                                                    ),
                                                    const DataColumn(
                                                      label: Text('جزئیات'),
                                                    ),
                                                  ],
                                                  rows: machines.map((machine) {
                                                    final status =
                                                        machine['status'];
                                                    final isActive =
                                                        status == 1;
                                                    return DataRow(
                                                      cells: [
                                                        _textCell(
                                                          machine['id'],
                                                        ),
                                                        _textCell(
                                                          machine['name'],
                                                        ),
                                                        _textCell(
                                                          machine['serial'],
                                                        ),
                                                        _textCell(
                                                          machine['model'],
                                                        ),
                                                        _textCell(
                                                          machine['manufacturer'],
                                                        ),
                                                        _textCell(
                                                          machine['location'],
                                                        ),
                                                        DataCell(
                                                          _StatusLabel(
                                                            label: isActive
                                                                ? 'فعال'
                                                                : status == 2
                                                                ? 'غیرفعال'
                                                                : 'نامشخص',
                                                            isActive: isActive,
                                                          ),
                                                        ),
                                                        _textCell(
                                                          machine['version'],
                                                        ),
                                                        _textCell(
                                                          machine['standby_time'],
                                                        ),
                                                        _textCell(
                                                          machine['cup_weight'],
                                                        ),
                                                        _textCell(
                                                          machine['boiler_temp_threshold'],
                                                        ),
                                                        DataCell(
                                                          Text(
                                                            _formatDate(
                                                              machine['creation_date'],
                                                            ),
                                                          ),
                                                        ),
                                                        DataCell(
                                                          IconButton(
                                                            tooltip:
                                                                'مشاهده جزئیات دستگاه',
                                                            onPressed: () =>
                                                                context.push(
                                                                  '${AdminMachineDetailsPage.routePath}/${Uri.encodeComponent(machine['serial'].toString())}',
                                                                ),
                                                            icon: const Icon(
                                                              Icons.open_in_new,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            ),
                                          ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : _buildLoginForm(context),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 44,
                  color: colors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'ورود مدیر',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'نام کاربری Django',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _signIn(),
                  decoration: const InputDecoration(
                    labelText: 'گذرواژه',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_loginError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _loginError!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isLoggingIn ? null : _signIn,
                  icon: _isLoggingIn
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('ورود به پنل مدیریت'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileField(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label)),
          Expanded(
            child: Text(
              _display(value),
              textAlign: TextAlign.start,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.isActive});

  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
