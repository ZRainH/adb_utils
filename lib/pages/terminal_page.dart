import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/log_entry.dart';
import '../models/logcat_options.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/empty_state.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.state});

  final AppState state;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  static const _stampTailCount = 80;

  final _filterController = TextEditingController();
  final _scrollController = ScrollController();
  final _listNotifier = ValueNotifier<List<LogEntry>>(const []);
  final _logs = <LogEntry>[];
  final _pending = <LogEntry>[];
  StreamSubscription<LogEntry>? _sub;
  LogLevel? _minLevel;
  final LogcatBuffer _buffer = LogcatBuffer.main;
  bool _autoScroll = true;
  bool _paused = false;
  String _filter = '';
  String _filterLower = '';
  String? _boundSerial;
  String? _streamError;
  String? _boundDefaultLevel;
  Timer? _flushTimer;
  Timer? _filterDebounce;
  bool _isProgrammaticScroll = false;
  List<LogEntry> _visibleLogs = const [];
  int _logBufferBytes = 0;

  String? get _serial => widget.state.selectedDevice?.id;

  int get _cycleBufferKb => widget.state.settings.logcatCycleBufferKb;

  String get _bufferLimitLabel =>
      _cycleBufferKb <= 0 ? '不限制' : '$_cycleBufferKb KB';

  int _entryBytes(LogEntry entry) => utf8.encode(entry.fullLine).length + 1;

  double get _fontSize => widget.state.settings.terminalFontSize;

  bool get _hasDisplayFilter => _filterLower.isNotEmpty || _minLevel != null;

  @override
  void initState() {
    super.initState();
    _boundSerial = _serial;
    _minLevel = LogLevel.fromName(widget.state.settings.defaultLogLevel);
    _boundDefaultLevel = widget.state.settings.defaultLogLevel;
    widget.state.addListener(_onState);
    _scrollController.addListener(_onUserScroll);
    _startLogcat();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _scrollController.removeListener(_onUserScroll);
    _flushTimer?.cancel();
    _filterDebounce?.cancel();
    _sub?.cancel();
    widget.state.adb.stopLogcat();
    _filterController.dispose();
    _scrollController.dispose();
    _listNotifier.dispose();
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    final serial = _serial;
    if (serial != _boundSerial) {
      _boundSerial = serial;
      _startLogcat();
      return;
    }
    if (_paused) return;

    final defaultLevel = widget.state.settings.defaultLogLevel;
    if (defaultLevel != _boundDefaultLevel) {
      _boundDefaultLevel = defaultLevel;
      final next = LogLevel.fromName(defaultLevel);
      if (next != _minLevel) {
        _minLevel = next;
        _startLogcat();
      }
    }

    final global = widget.state.searchQuery;
    if (global != _filter && global != _filterController.text) {
      _filterController.text = global;
      _applyFilter(global);
    }
  }

  void _applyFilter(String value, {bool immediate = false}) {
    _filter = value;
    _filterLower = value.toLowerCase().trim();
    _filterDebounce?.cancel();
    if (immediate) {
      _rebuildVisibleLogs();
      _publishLogs();
      return;
    }
    _filterDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _rebuildVisibleLogs();
      _publishLogs();
    });
  }

  void _commitSearchHistory(String value) {
    widget.state.submitSearch(value);
    if (mounted) setState(() {});
  }

  void _selectSearchHistory(String value) {
    _filterController.text = value;
    widget.state.setSearch(value);
    _applyFilter(value, immediate: true);
  }

  Widget _searchHistorySuffix() {
    final history = widget.state.settings.logcatSearchHistory;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_filter.isNotEmpty)
          IconButton(
            tooltip: '清除',
            icon: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
            onPressed: () {
              _filterController.clear();
              widget.state.setSearch('');
              _applyFilter('', immediate: true);
            },
          ),
        PopupMenuButton<String>(
          tooltip: '搜索历史',
          padding: EdgeInsets.zero,
          icon: Icon(Icons.arrow_drop_down, size: 20, color: AppColors.textSecondary),
          color: AppColors.surfaceElevated,
          onSelected: (value) async {
            if (value == '__clear__') {
              await widget.state.clearLogcatSearchHistory();
              if (mounted) setState(() {});
              return;
            }
            _selectSearchHistory(value);
          },
          itemBuilder: (context) {
            if (history.isEmpty) {
              return [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    '暂无历史',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ];
            }
            return [
              ...history.map(
                (item) => PopupMenuItem<String>(
                  value: item,
                  child: Text(item, overflow: TextOverflow.ellipsis),
                ),
              ),
              PopupMenuItem<String>(
                value: '__clear__',
                child: Text(
                  '清空历史',
                  style: TextStyle(color: AppColors.errorLog),
                ),
              ),
            ];
          },
        ),
      ],
    );
  }

  void _publishLogs() {
    _listNotifier.value = _visibleLogs;
  }

  void _rebuildVisibleLogs() {
    if (!_hasDisplayFilter) {
      _visibleLogs = List<LogEntry>.unmodifiable(_logs);
      return;
    }
    _visibleLogs = List<LogEntry>.unmodifiable([
      for (final e in _logs)
        if (e.matchesFast(_filterLower, _minLevel)) e,
    ]);
  }

  void _onUserScroll() {
    if (_isProgrammaticScroll || !_scrollController.hasClients || !_autoScroll || _paused) {
      return;
    }
    if (_scrollController.offset > 48) {
      setState(() => _autoScroll = false);
    }
  }

  void _setAutoScroll(bool enabled) {
    setState(() => _autoScroll = enabled);
    if (enabled && !_paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScroll && !_paused) _stickToBottom();
      });
    }
  }

  void _stickToBottom() {
    if (!_scrollController.hasClients || _paused) return;
    _isProgrammaticScroll = true;
    _scrollController.jumpTo(0);
    _isProgrammaticScroll = false;
  }

  void _stampRecentPackages() {
    if (_logs.isEmpty) return;
    final start = _logs.length > _stampTailCount ? _logs.length - _stampTailCount : 0;
    for (var i = start; i < _logs.length; i++) {
      final e = _logs[i];
      if (e.packageName != null && e.packageName!.isNotEmpty) continue;
      final pkg = widget.state.adb.packageForPid(e.pid);
      if (pkg == null || pkg.isEmpty) continue;
      _logs[i] = e.copyWith(packageName: pkg);
    }
  }

  void _flushBatch() {
    _flushTimer = null;
    if (!mounted || _paused || _pending.isEmpty) return;

    _logs.addAll(_pending);
    for (final entry in _pending) {
      _logBufferBytes += _entryBytes(entry);
    }
    _pending.clear();
    _trimLogs();
    _stampRecentPackages();
    _rebuildVisibleLogs();
    _publishLogs();

    if (_autoScroll && !_paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _autoScroll && !_paused) _stickToBottom();
      });
    }
  }

  void _scheduleBatchFlush() {
    if (_paused) return;
    _flushTimer ??= Timer(const Duration(milliseconds: 180), _flushBatch);
  }

  void _trimLogs() {
    // 按循环缓冲上限（KB）丢弃最旧日志；搜索/级别只影响显示，不影响缓冲容量。
    final maxKb = _cycleBufferKb;
    if (maxKb <= 0) return;
    final maxBytes = maxKb * 1024;
    while (_logs.isNotEmpty && _logBufferBytes > maxBytes) {
      _logBufferBytes -= _entryBytes(_logs.removeAt(0));
    }
  }

  Future<void> _startLogcat() async {
    await widget.state.adb.stopLogcat();
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pending.clear();
    if (!mounted) return;
    setState(() {
      _logs.clear();
      _visibleLogs = const [];
      _streamError = null;
      _paused = false;
      _logBufferBytes = 0;
    });
    _listNotifier.value = const [];

    final serial = _serial;
    if (serial == null) return;

    _sub = widget.state.adb
        .startLogcat(serial, buffer: _buffer, minLevel: _minLevel)
        .listen(
      (entry) {
        if (!mounted || _paused) return;
        _pending.add(entry);
        _scheduleBatchFlush();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _streamError = e.toString());
      },
    );
  }

  Future<void> _clearLogcat() async {
    final serial = _serial;
    if (serial != null) {
      try {
        await widget.state.adb.clearLogcatBuffer(serial);
      } catch (_) {}
    }
    _pending.clear();
    _logs.clear();
    _logBufferBytes = 0;
    _visibleLogs = const [];
    _listNotifier.value = const [];
    setState(() {});
  }

  void _togglePause() {
    final pausing = !_paused;
    setState(() => _paused = pausing);
    if (pausing) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _pending.clear();
      return;
    }
    _scheduleBatchFlush();
  }

  @override
  Widget build(BuildContext context) {
    if (_serial == null) {
      return EmptyStateView(
        title: '未选择设备',
        message: widget.state.lastError ?? '请先连接设备后再查看 Logcat。',
        actionLabel: '刷新设备',
        onAction: widget.state.refreshDevices,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          PanelCard(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterController,
                    onChanged: (value) {
                      widget.state.setSearch(value);
                      _applyFilter(value);
                    },
                    onSubmitted: (value) {
                      _commitSearchHistory(value);
                      _applyFilter(value, immediate: true);
                    },
                    style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: '搜索 Tag / 消息 / PID / pkg:包名…',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      prefixIcon: Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                      suffixIcon: _searchHistorySuffix(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _toolbarIcon(
                  tooltip: _paused ? '继续' : '暂停',
                  icon: _paused ? Icons.play_arrow : Icons.pause,
                  onPressed: _togglePause,
                  active: _paused,
                ),
                _toolbarIcon(
                  tooltip: '重启 Logcat',
                  icon: Icons.refresh,
                  onPressed: _startLogcat,
                ),
                _toolbarIcon(
                  tooltip: '清空（含设备缓冲区）',
                  icon: Icons.delete_outline,
                  onPressed: _clearLogcat,
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: AppColors.border,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(value: _autoScroll, onChanged: _paused ? null : _setAutoScroll),
                    Text('贴底', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceDeep,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Logcat',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.55,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_paused) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '已暂停',
                              style: TextStyle(fontSize: 10, color: AppColors.warning),
                            ),
                          ),
                        ],
                        const Spacer(),
                        ValueListenableBuilder<List<LogEntry>>(
                          valueListenable: _listNotifier,
                          builder: (context, logs, _) {
                            final label = _hasDisplayFilter
                                ? '${logs.length} 条匹配 · 缓冲 $_bufferLimitLabel'
                                : '${logs.length} 行 · 缓冲 $_bufferLimitLabel';
                            return Text(
                              label,
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _streamError != null
                        ? EmptyStateView(
                            icon: Icons.error_outline,
                            title: 'Logcat 连接失败',
                            message: _streamError!,
                            actionLabel: '重试',
                            onAction: _startLogcat,
                          )
                        : ValueListenableBuilder<List<LogEntry>>(
                            valueListenable: _listNotifier,
                            builder: (context, logs, _) {
                              if (logs.isEmpty) {
                                final message = _paused
                                    ? '已暂停接收日志'
                                    : _hasDisplayFilter && _logs.isNotEmpty
                                        ? '无匹配日志'
                                        : '等待 logcat 输出…';
                                return Center(
                                  child: Text(
                                    message,
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                );
                              }
                              return Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  reverse: true,
                                  addAutomaticKeepAlives: false,
                                  addRepaintBoundaries: true,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    final entry = logs[logs.length - 1 - index];
                                    return _LogLine(
                                      key: ValueKey('${entry.timestamp}-${entry.pid}-${entry.tag}-$index'),
                                      entry: entry,
                                      fontSize: _fontSize,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 20,
        color: active ? AppColors.accentBright : AppColors.textSecondary,
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({
    super.key,
    required this.entry,
    required this.fontSize,
  });

  final LogEntry entry;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final isError = entry.level == LogLevel.error;
    return GestureDetector(
      onSecondaryTap: () => _copy(context),
      onLongPress: () => _copy(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: isError ? AppColors.danger.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          entry.fullLine,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: fontSize,
            height: 1.35,
            color: entry.color,
          ),
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: entry.fullLine));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制日志行'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
  }
}
