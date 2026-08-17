import 'dart:async';

import 'package:flutter/material.dart';

import '../models/log_entry.dart';
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
  static const _maxFilteredKeepRatio = 2 / 3;

  final _filterController = TextEditingController();
  final _commandController = TextEditingController(text: 'shell input tap 500 500');
  final _scrollController = ScrollController();
  final List<LogEntry> _logs = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  StreamSubscription<LogEntry>? _sub;
  LogLevel? _levelFilter;
  bool _autoScroll = true;
  String _filter = '';
  String? _boundSerial;
  String? _streamError;
  String? _boundDefaultLevel;

  String? get _serial => widget.state.selectedDevice?.id;

  int get _maxLogs => widget.state.settings.logcatBufferSize.clamp(200, 20000);

  int get _maxFilteredKeep =>
      (_maxLogs * _maxFilteredKeepRatio).round().clamp(200, _maxLogs);

  double get _fontSize => widget.state.settings.terminalFontSize;

  bool get _hasFilter =>
      _filter.trim().isNotEmpty || _levelFilter != null;

  @override
  void initState() {
    super.initState();
    _boundSerial = _serial;
    _levelFilter = LogLevel.fromName(widget.state.settings.defaultLogLevel);
    _boundDefaultLevel = widget.state.settings.defaultLogLevel;
    widget.state.addListener(_onState);
    _scrollController.addListener(_onUserScroll);
    _startLogcat();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _scrollController.removeListener(_onUserScroll);
    _sub?.cancel();
    widget.state.adb.stopLogcat();
    _filterController.dispose();
    _commandController.dispose();
    _scrollController.dispose();
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
    final defaultLevel = widget.state.settings.defaultLogLevel;
    if (defaultLevel != _boundDefaultLevel) {
      _boundDefaultLevel = defaultLevel;
      _levelFilter = LogLevel.fromName(defaultLevel);
    }
    // Sync top-bar search into log filter when on this page.
    final global = widget.state.searchQuery;
    if (global != _filter && global != _filterController.text) {
      _filterController.text = global;
      setState(() => _filter = global);
      return;
    }
    // Process map may have updated — stamp missing package names.
    if (_stampMissingPackages()) {
      setState(() {});
      return;
    }
    setState(() {});
  }

  /// reverse:true ListView：offset==0 表示底部（最新日志）。
  void _onUserScroll() {
    if (!_scrollController.hasClients || !_autoScroll) return;
    // 用户往上翻离开底部时，自动关闭「贴底滚动」。
    if (_scrollController.offset > 48) {
      setState(() => _autoScroll = false);
    }
  }

  void _setAutoScroll(bool enabled) {
    setState(() => _autoScroll = enabled);
    if (enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  LogEntry _withPackage(LogEntry entry) {
    if (entry.packageName != null && entry.packageName!.isNotEmpty) return entry;
    final pkg = widget.state.adb.packageForPid(entry.pid);
    if (pkg == null || pkg.isEmpty) return entry;
    return entry.copyWith(packageName: pkg);
  }

  /// Permanently write discovered package names onto buffered entries.
  bool _stampMissingPackages() {
    var changed = false;
    for (var i = 0; i < _logs.length; i++) {
      final e = _logs[i];
      if (e.packageName != null && e.packageName!.isNotEmpty) continue;
      final pkg = widget.state.adb.packageForPid(e.pid);
      if (pkg == null || pkg.isEmpty) continue;
      _logs[i] = e.copyWith(packageName: pkg);
      changed = true;
    }
    return changed;
  }

  void _appendLog(LogEntry entry) {
    _logs.add(_withPackage(entry));
    _trimLogs();
  }

  /// Drop oldest logs, but when filtering prefer dropping non-matches first
  /// so filtered results don't vanish under log flood.
  void _trimLogs() {
    if (!_hasFilter) {
      if (_logs.length > _maxLogs) {
        _logs.removeRange(0, _logs.length - _maxLogs);
      }
      return;
    }

    if (_logs.length > _maxLogs) {
      final removeIdx = <int>[];
      var excess = _logs.length - _maxLogs;
      for (var i = 0; i < _logs.length && excess > 0; i++) {
        if (!_logs[i].matches(_filter, _levelFilter)) {
          removeIdx.add(i);
          excess--;
        }
      }
      for (var i = removeIdx.length - 1; i >= 0; i--) {
        _logs.removeAt(removeIdx[i]);
      }
    }

    if (_logs.length > _maxFilteredKeep) {
      // Still over: all (or mostly) matches — keep the newest matches.
      final matching = <LogEntry>[];
      for (final e in _logs) {
        if (e.matches(_filter, _levelFilter)) matching.add(e);
      }
      if (matching.length > _maxFilteredKeep) {
        final keep = matching.sublist(matching.length - _maxFilteredKeep);
        _logs
          ..clear()
          ..addAll(keep);
      } else if (_logs.length > _maxFilteredKeep) {
        _logs.removeRange(0, _logs.length - _maxFilteredKeep);
      }
    }
  }

  Future<void> _startLogcat() async {
    await widget.state.adb.stopLogcat();
    await _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() {
      _logs.clear();
      _streamError = null;
    });

    final serial = _serial;
    if (serial == null) return;

    _sub = widget.state.adb.startLogcat(serial).listen(
      (entry) {
        if (!mounted) return;
        setState(() => _appendLog(entry));
        if (_autoScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _streamError = e.toString());
      },
    );
  }

  List<LogEntry> get _visible {
    _stampMissingPackages();
    if (!_hasFilter) return _logs;
    return [
      for (final e in _logs)
        if (e.matches(_filter, _levelFilter)) e,
    ];
  }

  Future<void> _execute() async {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;
    _history.insert(0, cmd);
    _historyIndex = -1;
    final output = await widget.state.adb.runCommand(_serial, cmd);
    if (!mounted) return;
    setState(() {
      _logs.add(
        LogEntry(
          timestamp: _nowStamp(),
          pid: '0000',
          tid: '0000',
          level: LogLevel.info,
          tag: 'adb',
          message: '>> adb $cmd\n$output',
        ),
      );
    });
  }

  String _nowStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}:${two(n.second)}.${n.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_serial == null) {
      return EmptyStateView(
        title: '未选择设备',
        message: widget.state.lastError ?? '请先连接设备后再查看 logcat / 执行命令。',
        actionLabel: '刷新设备',
        onAction: widget.state.refreshDevices,
      );
    }

    final logs = _visible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        children: [
          PanelCard(
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 448),
                    child: TextField(
                      controller: _filterController,
                      onChanged: (v) => setState(() => _filter = v),
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: '按包名、标签、PID 或内容筛选…',
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        prefixIcon: Icon(
                          Icons.search,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
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
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LogLevel?>(
                      value: _levelFilter,
                      dropdownColor: AppColors.surfaceElevated,
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('全部级别')),
                        DropdownMenuItem(value: LogLevel.verbose, child: Text('详细')),
                        DropdownMenuItem(value: LogLevel.debug, child: Text('调试')),
                        DropdownMenuItem(value: LogLevel.info, child: Text('信息')),
                        DropdownMenuItem(value: LogLevel.warning, child: Text('警告')),
                        DropdownMenuItem(value: LogLevel.error, child: Text('错误')),
                      ],
                      onChanged: (v) => setState(() => _levelFilter = v),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(width: 1, height: 28, color: AppColors.border),
                const SizedBox(width: 16),
                Row(
                  children: [
                    Switch(
                      value: _autoScroll,
                      onChanged: _setAutoScroll,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '自动滚动',
                      style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                ActionButton(
                  label: '清空',
                  icon: Icons.delete_outline,
                  onPressed: () => setState(() => _logs.clear()),
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
                          'ADB 日志',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.55,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        _dot(const Color(0x80FFB4AB)),
                        const SizedBox(width: 6),
                        _dot(const Color(0x80CEC2DB)),
                        const SizedBox(width: 6),
                        _dot(const Color(0x808ECDFF)),
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
                        : logs.isEmpty
                            ? Center(
                                child: Text(
                                  '等待 logcat 输出…',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                itemCount: logs.length,
                                itemBuilder: (context, index) {
                                  // reverse:true → index 0 在底部，对应最新日志。
                                  final entry = logs[logs.length - 1 - index];
                                  final isError = entry.level == LogLevel.error;
                                  final pkg = entry.packageName;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isError
                                          ? AppColors.danger.withValues(alpha: 0.25)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: SelectableText.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontFamily: 'Consolas',
                                          fontSize: _fontSize,
                                          height: 1.6,
                                          color: entry.color,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: '${entry.timestamp}  ',
                                            style: TextStyle(
                                              color: entry.color.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          TextSpan(
                                            text:
                                                '${entry.pid.padLeft(4)}  ${entry.tid.padLeft(4)}  ',
                                            style: TextStyle(
                                              color: entry.color.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          TextSpan(
                                            text: '${entry.levelCode}  ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: entry.color,
                                            ),
                                          ),
                                          if (pkg != null && pkg.isNotEmpty)
                                            TextSpan(
                                              text: '$pkg  ',
                                              style: TextStyle(
                                                color: entry.color.withValues(alpha: 0.65),
                                              ),
                                            ),
                                          TextSpan(text: '${entry.tag}: '),
                                          TextSpan(text: entry.message),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '>> adb',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: _fontSize + 1,
                  color: AppColors.accentBright,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _commandController,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: _fontSize + 1,
                    color: AppColors.textPrimary,
                  ),
                  onSubmitted: (_) => _execute(),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    suffixIcon: IconButton(
                      tooltip: '历史命令',
                      onPressed: () {
                        if (_history.isEmpty) return;
                        _historyIndex = (_historyIndex + 1) % _history.length;
                        _commandController.text = _history[_historyIndex];
                      },
                      icon: Icon(Icons.history, size: 18, color: AppColors.textSecondary),
                    ),
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
              const SizedBox(width: 12),
              ActionButton(
                label: '执行',
                icon: Icons.play_arrow,
                filled: true,
                onPressed: _execute,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
