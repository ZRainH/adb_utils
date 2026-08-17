import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device_database.dart';
import '../services/app_settings.dart';
import '../services/app_state.dart';
import '../services/device_db_service.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/empty_state.dart';

enum _TableRefreshMode { off, timed, realtime }

class DatabaseViewerPage extends StatefulWidget {
  const DatabaseViewerPage({super.key, required this.state});

  final AppState state;

  @override
  State<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends State<DatabaseViewerPage> {
  late final DeviceDbService _dbService = DeviceDbService(widget.state.adb);

  List<DeviceDatabase> _databases = const [];
  DeviceDatabase? _selected;
  List<String> _tables = const [];
  String? _selectedTable;
  DbQueryResult _result = DbQueryResult.empty;

  final _queryController = TextEditingController();
  bool _consoleExpanded = true;
  bool _loadingList = false;
  bool _loadingTables = false;
  bool _loadingQuery = false;
  bool _refreshingQuiet = false;
  String? _error;
  String? _boundSerial;
  String? _boundPackageFilter;

  _TableRefreshMode _refreshMode = _TableRefreshMode.off;
  int _timedSeconds = 5;
  Timer? _refreshTimer;
  DateTime? _lastRefreshedAt;
  int _refreshToken = 0;

  String? get _serial => widget.state.selectedDevice?.id;
  String? get _packageFilter => widget.state.dbPackageFilter;
  int get _queryLimit => widget.state.settings.dbQueryLimit;

  String _selectSql(String table) => 'SELECT * FROM $table LIMIT $_queryLimit;';

  void _applySettingsDefaults() {
    _refreshMode = switch (widget.state.settings.dbRefreshMode) {
      DbRefreshPref.off => _TableRefreshMode.off,
      DbRefreshPref.timed => _TableRefreshMode.timed,
      DbRefreshPref.realtime => _TableRefreshMode.realtime,
    };
    _timedSeconds = widget.state.settings.dbRefreshSeconds;
  }

  Duration get _refreshInterval {
    switch (_refreshMode) {
      case _TableRefreshMode.off:
        return Duration.zero;
      case _TableRefreshMode.realtime:
        return const Duration(seconds: 1);
      case _TableRefreshMode.timed:
        return Duration(seconds: _timedSeconds);
    }
  }

  @override
  void initState() {
    super.initState();
    _boundSerial = _serial;
    _boundPackageFilter = _packageFilter;
    _applySettingsDefaults();
    widget.state.addListener(_onState);
    _refreshDatabases();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    widget.state.removeListener(_onState);
    _queryController.dispose();
    super.dispose();
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _syncAutoRefresh() {
    _stopAutoRefresh();
    if (_refreshMode == _TableRefreshMode.off) return;
    if (_selected == null || _serial == null) return;
    final interval = _refreshInterval;
    if (interval <= Duration.zero) return;
    _refreshTimer = Timer.periodic(interval, (_) {
      unawaited(_refreshTableData(quiet: true));
    });
  }

  void _setRefreshMode(_TableRefreshMode mode) {
    setState(() => _refreshMode = mode);
    _syncAutoRefresh();
    if (mode != _TableRefreshMode.off) {
      unawaited(_refreshTableData(quiet: true));
    }
  }

  void _setTimedSeconds(int seconds) {
    setState(() => _timedSeconds = seconds);
    if (_refreshMode == _TableRefreshMode.timed) {
      _syncAutoRefresh();
    }
  }

  void _onState() {
    if (!mounted) return;
    final serial = _serial;
    final packageFilter = _packageFilter;
    if (serial != _boundSerial || packageFilter != _boundPackageFilter) {
      _boundSerial = serial;
      _boundPackageFilter = packageFilter;
      _stopAutoRefresh();
      _dbService.invalidateCache();
      setState(() {
        _databases = const [];
        _selected = null;
        _tables = const [];
        _selectedTable = null;
        _result = DbQueryResult.empty;
        _error = null;
        _applySettingsDefaults();
        _queryController.clear();
      });
      _refreshDatabases();
      return;
    }
    setState(() {});
  }

  Future<void> _refreshDatabases() async {
    final serial = _serial;
    if (serial == null) {
      setState(() {
        _databases = const [];
        _selected = null;
        _tables = const [];
        _selectedTable = null;
        _result = DbQueryResult.empty;
        _loadingList = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loadingList = true;
      _error = null;
    });

    try {
      final list = await _dbService.listDatabases(
        serial,
        packageName: _packageFilter,
      );
      if (!mounted) return;
      setState(() {
        _databases = list;
        _loadingList = false;
        if (_selected != null) {
          final still = list.where((d) => d.remotePath == _selected!.remotePath);
          _selected = still.isNotEmpty ? still.first : (list.isNotEmpty ? list.first : null);
        } else if (list.isNotEmpty) {
          _selected = list.first;
        } else {
          _selected = null;
          _tables = const [];
          _selectedTable = null;
          _result = DbQueryResult.empty;
        }
      });
      if (_selected != null) {
        await _loadTables(_selected!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectDatabase(DeviceDatabase db) async {
    if (_selected?.remotePath == db.remotePath) return;
    setState(() {
      _selected = db;
      _tables = const [];
      _selectedTable = null;
      _result = DbQueryResult.empty;
      _error = null;
    });
    await _loadTables(db);
    _syncAutoRefresh();
  }

  Future<void> _loadTables(DeviceDatabase db) async {
    final serial = _serial;
    if (serial == null) return;

    setState(() {
      _loadingTables = true;
      _error = null;
    });

    try {
      final tables = await _dbService.listTables(serial, db);
      if (!mounted) return;
      final preferred = tables.contains(_selectedTable)
          ? _selectedTable
          : (tables.isNotEmpty ? tables.first : null);
      setState(() {
        _tables = tables;
        _selectedTable = preferred;
        _loadingTables = false;
        if (preferred != null) {
          _queryController.text = _selectSql(preferred);
        }
      });
      if (preferred != null) {
        await _runQuery();
      }
      _syncAutoRefresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tables = const [];
        _selectedTable = null;
        _loadingTables = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onTableChanged(String? table) async {
    if (table == null) return;
    setState(() {
      _selectedTable = table;
      _queryController.text = _selectSql(table);
    });
    await _runQuery();
    _syncAutoRefresh();
  }

  Future<void> _runQuery({bool quiet = false}) async {
    final serial = _serial;
    final db = _selected;
    if (serial == null || db == null) return;

    final sql = _queryController.text.trim();
    if (sql.isEmpty) return;

    final token = ++_refreshToken;
    if (!quiet) {
      setState(() {
        _loadingQuery = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _refreshingQuiet = true);
    }

    try {
      final result = await _dbService.query(serial, db, sql, limit: 200);
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _result = result;
        _loadingQuery = false;
        _refreshingQuiet = false;
        _lastRefreshedAt = DateTime.now();
        _error = null;
      });
    } catch (e) {
      if (!mounted || token != _refreshToken) return;
      setState(() {
        _loadingQuery = false;
        _refreshingQuiet = false;
        if (!quiet) _error = e.toString();
      });
    }
  }

  /// Re-pull DB from device then re-run current SQL.
  Future<void> _refreshTableData({bool quiet = false}) async {
    final serial = _serial;
    final db = _selected;
    if (serial == null || db == null) return;
    if (_loadingQuery && !quiet) return;
    if (_refreshingQuiet && quiet) return;

    _dbService.invalidateCache(serial: serial, remotePath: db.remotePath);
    await _runQuery(quiet: quiet);
  }

  Future<void> _exportCsv() async {
    final serial = _serial;
    final db = _selected;
    if (serial == null || db == null) return;

    final sql = _queryController.text.trim().isNotEmpty
        ? _queryController.text.trim()
        : (_selectedTable != null
            ? 'SELECT * FROM $_selectedTable LIMIT 5000;'
            : null);
    if (sql == null) return;

    final dir = widget.state.settings.effectiveSaveDirectory;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path =
        '$dir${Platform.pathSeparator}'
        '${db.name.replaceAll('.db', '')}_${_selectedTable ?? 'query'}_$stamp.csv';

    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {}

    setState(() => _loadingQuery = true);
    try {
      final saved = await _dbService.exportCsv(serial, db, sql, path);
      if (!mounted) return;
      setState(() => _loadingQuery = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导出：$saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingQuery = false;
        _error = e.toString();
      });
    }
  }

  List<DeviceDatabase> get _filteredDatabases {
    final q = widget.state.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _databases;
    return _databases
        .where(
          (d) =>
              d.name.toLowerCase().contains(q) ||
              d.remotePath.toLowerCase().contains(q) ||
              (d.packageName?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  DbQueryResult get _filteredResult {
    final q = widget.state.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _result;
    // Prefer filtering rows when a table is open; also match table names.
    final cols = _result.columns;
    final rows = _result.rows.where((row) {
      for (final cell in row) {
        if (cell.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
    if (rows.isEmpty &&
        _tables.any((t) => t.toLowerCase().contains(q)) &&
        _result.rows.isNotEmpty) {
      return _result;
    }
    return DbQueryResult(columns: cols, rows: rows);
  }

  int? _deletedColumnIndex(List<String> columns) {
    final i = columns.indexWhere((c) => c.toLowerCase() == 'deleted');
    return i >= 0 ? i : null;
  }

  bool _rowDeleted(List<String> row, int? deletedIdx) {
    if (deletedIdx == null || deletedIdx >= row.length) return false;
    final v = row[deletedIdx].trim();
    return v == '1' || v.toLowerCase() == 'true';
  }

  bool _looksLikeIdColumn(String name) {
    final n = name.toLowerCase();
    return n == '_id' || n.endsWith('_id') || n == 'id';
  }

  @override
  Widget build(BuildContext context) {
    final serial = _serial;
    if (serial == null) {
      return const EmptyStateView(
        title: '未连接设备',
        message: '请连接已开启 USB 调试的设备后查看数据库。',
        icon: Icons.storage_outlined,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 280, child: _buildDatabaseList()),
          const SizedBox(width: 12),
          Expanded(child: _buildMainPanel()),
        ],
      ),
    );
  }

  Widget _buildDatabaseList() {
    final items = _filteredDatabases;
    return PanelCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _packageFilter == null ? '数据库' : '应用数据库',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loadingList ? null : _refreshDatabases,
                  icon: _loadingList
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (_packageFilter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.apps_rounded, size: 14, color: AppColors.accentBright),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _packageFilter!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Consolas',
                          color: AppColors.accentOn,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: widget.state.clearDbPackageFilter,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 14, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _loadingList
                            ? '正在扫描设备上的数据库…'
                            : _packageFilter != null
                                ? '该应用下未找到可读数据库。\n需可调试（run-as）或 root，也可将 .db 拷到 /sdcard。'
                                : '未找到可读数据库。\n可调试应用的 databases/ 或 /sdcard 下的 .db 文件会出现在此。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final db = items[index];
                      final selected = _selected?.remotePath == db.remotePath;
                      return InkWell(
                        onTap: () => _selectDatabase(db),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: 0.18)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selected ? AppColors.accentBright : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                db.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                db.directory,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainPanel() {
    if (_selected == null) {
      return const EmptyStateView(
        title: '选择数据库',
        message: '从左侧列表选择一个 .db 文件以浏览表与数据。',
        icon: Icons.table_chart_outlined,
      );
    }

    final result = _filteredResult;
    final deletedIdx = _deletedColumnIndex(result.columns);

    return Column(
      children: [
        Expanded(
          child: PanelCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '表：',
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _tables.contains(_selectedTable) ? _selectedTable : null,
                            hint: Text(
                              _loadingTables ? '加载中…' : '选择表',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                            ),
                            dropdownColor: AppColors.surfaceElevated,
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                            items: _tables
                                .map(
                                  (t) => DropdownMenuItem(value: t, child: Text(t)),
                                )
                                .toList(),
                            onChanged: _loadingTables ? null : _onTableChanged,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.chip,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_tables.length} 张表',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 4,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          children: [
                            _buildRefreshControls(),
                            const SizedBox(width: 10),
                            ActionButton(
                              label: '导出 CSV',
                              icon: Icons.download_outlined,
                              filled: true,
                              onPressed: (_loadingQuery || _selectedTable == null)
                                  ? null
                                  : _exportCsv,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 12, color: AppColors.errorLog),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                  child: _loadingQuery || _loadingTables
                      ? const Center(child: CircularProgressIndicator())
                      : result.columns.isEmpty
                          ? Center(
                              child: Text(
                                '无数据',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: _buildDataTable(result, deletedIdx),
                                ),
                                if (_refreshingQuiet)
                                  const Positioned(
                                    right: 8,
                                    top: 8,
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildQueryConsole(),
      ],
    );
  }

  Widget _buildRefreshControls() {
    String modeLabel(_TableRefreshMode mode) {
      return switch (mode) {
        _TableRefreshMode.off => '关闭',
        _TableRefreshMode.timed => '定时',
        _TableRefreshMode.realtime => '实时',
      };
    }

    final last = _lastRefreshedAt;
    final lastText = last == null
        ? null
        : '${last.hour.toString().padLeft(2, '0')}:'
            '${last.minute.toString().padLeft(2, '0')}:'
            '${last.second.toString().padLeft(2, '0')}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '刷新表数据',
          onPressed: (_selectedTable == null || _loadingQuery)
              ? null
              : () => _refreshTableData(quiet: false),
          icon: Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(width: 4),
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _refreshMode == _TableRefreshMode.off
                  ? AppColors.border
                  : AppColors.accentBright.withValues(alpha: 0.55),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_TableRefreshMode>(
              value: _refreshMode,
              dropdownColor: AppColors.surfaceElevated,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              items: _TableRefreshMode.values
                  .map(
                    (m) => DropdownMenuItem(
                      value: m,
                      child: Text('刷新：${modeLabel(m)}'),
                    ),
                  )
                  .toList(),
              onChanged: (m) {
                if (m != null) _setRefreshMode(m);
              },
            ),
          ),
        ),
        if (_refreshMode == _TableRefreshMode.timed) ...[
          const SizedBox(width: 6),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _timedSeconds,
                dropdownColor: AppColors.surfaceElevated,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                items: const [2, 5, 10, 30]
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text('$s 秒')),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) _setTimedSeconds(s);
                },
              ),
            ),
          ),
        ],
        if (_refreshMode == _TableRefreshMode.realtime) ...[
          const SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF4CAF50),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '1 秒',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        if (lastText != null) ...[
          const SizedBox(width: 8),
          Text(
            lastText,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildDataTable(DbQueryResult result, int? deletedIdx) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.surfaceMuted),
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 52,
                  columns: [
                    for (final col in result.columns)
                      DataColumn(
                        label: Text(
                          col,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                  rows: [
                    for (final row in result.rows)
                      DataRow(
                        cells: [
                          for (var i = 0; i < result.columns.length; i++)
                            DataCell(
                              _cellText(
                                result.columns[i],
                                i < row.length ? row[i] : '',
                                deleted: _rowDeleted(row, deletedIdx),
                                isDeletedCol: deletedIdx == i,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cellText(
    String column,
    String value, {
    required bool deleted,
    required bool isDeletedCol,
  }) {
    Color color = AppColors.textPrimary;
    if (isDeletedCol && (value == '1' || value.toLowerCase() == 'true')) {
      color = AppColors.errorLog;
    } else if (_looksLikeIdColumn(column) && column.toLowerCase() != '_id') {
      color = AppColors.accentBright;
    }

    return SelectableText(
      value,
      style: TextStyle(
        fontSize: 13,
        color: color,
        decoration: deleted ? TextDecoration.lineThrough : TextDecoration.none,
        decorationColor: AppColors.textMuted,
      ),
    );
  }

  Widget _buildQueryConsole() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: _consoleExpanded ? 192 : 44,
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _consoleExpanded = !_consoleExpanded),
            child: SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '查询控制台',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      _consoleExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_consoleExpanded) ...[
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: TextField(
                  controller: _queryController,
                  maxLines: null,
                  expands: true,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'SELECT * FROM table_name LIMIT $_queryLimit;',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    isCollapsed: true,
                  ),
                  onSubmitted: (_) => _runQuery(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _queryController.text));
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('复制'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  ActionButton(
                    label: '执行',
                    icon: Icons.play_arrow_rounded,
                    filled: true,
                    onPressed: _loadingQuery ? null : _runQuery,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
