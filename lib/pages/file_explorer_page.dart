import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/empty_state.dart';

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({super.key, required this.state});

  final AppState state;

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  final List<String> _segments = ['设备', 'sdcard'];
  List<FileEntry> _files = const [];
  final Set<String> _selected = {};
  bool _loading = false;
  String? _error;
  String? _boundSerial;
  String? _runAsPackage;
  int _boundNavToken = 0;

  String? get _serial => widget.state.selectedDevice?.id;

  String get _currentPath {
    if (_segments.length <= 1) return '/sdcard';
    return '/${_segments.skip(1).join('/')}';
  }

  String? get _effectiveRunAs {
    final pkg = _runAsPackage;
    if (pkg == null) return null;
    if (_currentPath == '/data/data/$pkg' ||
        _currentPath.startsWith('/data/data/$pkg/')) {
      return pkg;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _boundSerial = _serial;
    _boundNavToken = widget.state.filesNavToken;
    widget.state.addListener(_onState);
    final pending = widget.state.filesTargetPath;
    if (pending != null && widget.state.filesNavToken > 0) {
      _applyTargetPath(pending, widget.state.filesRunAsPackage);
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    final serial = _serial;
    if (serial != _boundSerial) {
      _boundSerial = serial;
      setState(() {
        _segments
          ..clear()
          ..addAll(['设备', 'sdcard']);
        _runAsPackage = null;
      });
      _load();
      return;
    }
    if (widget.state.filesNavToken != _boundNavToken) {
      _boundNavToken = widget.state.filesNavToken;
      final target = widget.state.filesTargetPath;
      if (target != null) {
        _applyTargetPath(target, widget.state.filesRunAsPackage);
        return;
      }
    }
    setState(() {});
  }

  void _applyTargetPath(String path, String? runAsPackage) {
    var normalized = path.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized.split('/').where((s) => s.isNotEmpty).toList();
    setState(() {
      _segments
        ..clear()
        ..add('设备')
        ..addAll(parts.isEmpty ? ['sdcard'] : parts);
      _runAsPackage = runAsPackage;
      _selected.clear();
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    final serial = _serial;
    if (serial == null) {
      setState(() {
        _files = const [];
        _loading = false;
        _error = null;
        _selected.clear();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = _currentPath;
      final runAs = _effectiveRunAs;
      List<FileEntry> files;
      try {
        files = await widget.state.adb.listFiles(
          serial,
          path,
          runAsPackage: runAs,
        );
      } catch (e) {
        // Prefer external app-bound dir when private/cache path fails.
        final pkg = runAs ?? widget.state.filesRunAsPackage;
        if (pkg != null &&
            (path.contains('/data/data/$pkg') || path.contains('/Android/data/'))) {
          final fallbacks = <({String path, String? runAs})>[
            (path: '/sdcard/Android/data/$pkg', runAs: null),
            (path: '/sdcard/Android/data/$pkg/files', runAs: null),
            (path: '/sdcard/Android/data/$pkg/cache', runAs: null),
            (path: '/data/data/$pkg', runAs: pkg),
          ];
          Object? lastError = e;
          for (final fb in fallbacks) {
            if (fb.path == path) continue;
            try {
              final alt = await widget.state.adb.listFiles(
                serial,
                fb.path,
                runAsPackage: fb.runAs,
              );
              if (!mounted) return;
              final parts =
                  fb.path.split('/').where((s) => s.isNotEmpty).toList();
              setState(() {
                _segments
                  ..clear()
                  ..add('设备')
                  ..addAll(parts);
                _runAsPackage = fb.runAs;
                _files = alt;
                _selected.clear();
                _loading = false;
                _error = null;
              });
              return;
            } catch (err) {
              lastError = err;
            }
          }
          throw lastError ?? e;
        }
        rethrow;
      }
      if (!mounted) return;
      setState(() {
        _files = files;
        _selected.clear();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _files = const [];
        _selected.clear();
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openFolder(FileEntry entry) {
    if (!entry.isDirectory) return;
    setState(() => _segments.add(entry.name));
    _load();
  }

  void _goToSegment(int index) {
    setState(() => _segments.removeRange(index + 1, _segments.length));
    _load();
  }

  List<FileEntry> get _filtered {
    final q = widget.state.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _files;
    return _files.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  IconData _iconFor(FileKind kind) {
    switch (kind) {
      case FileKind.folder:
        return Icons.folder;
      case FileKind.image:
        return Icons.image_outlined;
      case FileKind.apk:
        return Icons.android;
      case FileKind.text:
        return Icons.description_outlined;
      case FileKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  Future<void> _jumpToPath() async {
    final path = await _promptPath(
      context,
      '跳转到路径',
      '/sdcard/Android/data/com.example/files',
    );
    if (path == null || path.trim().isEmpty) return;
    final trimmed = path.trim();
    String? runAs;
    final dataMatch = RegExp(r'^/data/data/([^/]+)').firstMatch(trimmed);
    if (dataMatch != null) {
      runAs = dataMatch.group(1);
    }
    _applyTargetPath(trimmed, runAs);
  }

  Future<void> _upload() async {
    final serial = _serial;
    if (serial == null) return;
    final path = await _promptPath(context, '上传本地文件', r'C:\path\to\file');
    if (path == null || path.isEmpty) return;
    final error = await widget.state.adb.pushFile(serial, path, _currentPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '上传完成')),
    );
    if (error == null) _load();
  }

  Future<void> _download() async {
    final serial = _serial;
    if (serial == null || _selected.isEmpty) return;
    final localDir = await _promptPath(context, '保存到本地文件夹', r'C:\Users\Public');
    if (localDir == null || localDir.isEmpty) return;
    String? lastError;
    for (final remote in _selected) {
      final name = remote.split('/').last;
      final local = '$localDir${localDir.endsWith('\\') || localDir.endsWith('/') ? '' : '\\'}$name';
      lastError = await widget.state.adb.pullFile(serial, remote, local);
      if (lastError != null) break;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(lastError ?? '已下载 ${_selected.length} 项')),
    );
  }

  Future<void> _newFolder() async {
    final serial = _serial;
    if (serial == null) return;
    final name = await _promptPath(context, '新建文件夹', '新建文件夹');
    if (name == null || name.isEmpty) return;
    try {
      await widget.state.adb.createFolder(serial, '$_currentPath/$name');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件夹已创建')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSelected() async {
    final serial = _serial;
    if (serial == null || _selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('删除所选内容？'),
        content: Text('将删除 ${_selected.length} 项，此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.state.adb.deletePaths(serial, _selected.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_serial == null) {
      return EmptyStateView(
        title: '未选择设备',
        message: widget.state.lastError ?? '请先连接设备后再浏览文件。',
        actionLabel: '刷新设备',
        onAction: widget.state.refreshDevices,
      );
    }

    final files = _filtered;
    final free = widget.state.storage.freeGb;
    final total = widget.state.storage.totalGb;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          PanelCard(
            child: Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < _segments.length; i++) ...[
                            if (i > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            InkWell(
                              onTap: () => _goToSegment(i),
                              child: Text(
                                _segments[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'Consolas',
                                  fontWeight: i == _segments.length - 1
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: i == _segments.length - 1
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_effectiveRunAs != null ||
                    _currentPath.contains('/Android/data/')) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.accentBright.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _currentPath.contains('/Android/data/')
                          ? '应用外部目录'
                          : '应用私有目录',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.accentOn,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                ActionButton(
                  label: '跳转',
                  icon: Icons.input,
                  onPressed: _jumpToPath,
                ),
                const SizedBox(width: 12),
                ActionButton(label: '上传', icon: Icons.upload, filled: true, onPressed: _upload),
                const SizedBox(width: 8),
                ActionButton(
                  label: '下载',
                  icon: Icons.download,
                  onPressed: _selected.isEmpty ? null : _download,
                ),
                const SizedBox(width: 8),
                ActionButton(
                  label: '新建文件夹',
                  icon: Icons.create_new_folder_outlined,
                  onPressed: _newFolder,
                ),
                const SizedBox(width: 8),
                ActionButton(
                  label: '删除',
                  icon: Icons.delete_outline,
                  danger: true,
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 2),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    color: AppColors.surfaceMuted,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value: files.isNotEmpty && _selected.length == files.length,
                            tristate: true,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selected
                                    ..clear()
                                    ..addAll(files.map((f) => f.path));
                                } else {
                                  _selected.clear();
                                }
                              });
                            },
                          ),
                        ),
                        const Expanded(
                          flex: 6,
                          child: Row(
                            children: [
                              Text('名称', style: _headerStyle),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                        const Expanded(flex: 2, child: Text('大小', style: _headerStyle)),
                        const Expanded(flex: 3, child: Text('修改时间', style: _headerStyle)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : _error != null
                            ? EmptyStateView(
                                icon: Icons.folder_off_outlined,
                                title: '无法打开目录',
                                message: _error!,
                                actionLabel: '重试',
                                onAction: _load,
                              )
                            : files.isEmpty
                                ? const EmptyStateView(
                                    icon: Icons.folder_open,
                                    title: '空目录',
                                    message: '当前路径下没有文件。',
                                  )
                                : ListView.builder(
                                    itemCount: files.length,
                                    itemBuilder: (context, index) {
                                      final file = files[index];
                                      final selected = _selected.contains(file.path);
                                      return Material(
                                        color: selected
                                            ? AppColors.surfaceMuted.withValues(alpha: 0.5)
                                            : Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (selected) {
                                                _selected.remove(file.path);
                                              } else {
                                                _selected.add(file.path);
                                              }
                                            });
                                          },
                                          onDoubleTap: () => _openFolder(file),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            decoration: const BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(color: AppColors.borderSoft),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 40,
                                                  child: Checkbox(
                                                    value: selected,
                                                    onChanged: (v) {
                                                      setState(() {
                                                        if (v == true) {
                                                          _selected.add(file.path);
                                                        } else {
                                                          _selected.remove(file.path);
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 6,
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        _iconFor(file.kind),
                                                        size: 18,
                                                        color: file.kind == FileKind.folder
                                                            ? AppColors.accentBright
                                                            : AppColors.textSecondary,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Flexible(
                                                        child: Text(
                                                          file.name,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                            color: AppColors.textPrimary,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    file.sizeLabel,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    file.modified,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${files.length} 项（已选 ${_selected.length}）',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                total <= 0
                    ? '可用空间：—'
                    : '可用空间：${free.toStringAsFixed(1)} GB / ${total.toStringAsFixed(0)} GB',
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<String?> _promptPath(BuildContext context, String title, String hint) {
    final controller = TextEditingController(text: hint.contains(r'\') ? '' : hint);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

const _headerStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: AppColors.textSecondary,
);
