import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/file_entry.dart';
import '../services/adb_service.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';

Future<void> showFilePreviewDialog(
  BuildContext context, {
  required AppState state,
  required FileEntry entry,
  String? runAsPackage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _FilePreviewDialog(
      state: state,
      entry: entry,
      runAsPackage: runAsPackage,
    ),
  );
}

class _FilePreviewDialog extends StatefulWidget {
  const _FilePreviewDialog({
    required this.state,
    required this.entry,
    this.runAsPackage,
  });

  final AppState state;
  final FileEntry entry;
  final String? runAsPackage;

  @override
  State<_FilePreviewDialog> createState() => _FilePreviewDialogState();
}

class _FilePreviewDialogState extends State<_FilePreviewDialog> {
  FilePreviewData? _data;
  bool _loading = true;

  String? get _serial => widget.state.selectedDevice?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final serial = _serial;
    if (serial == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = const FilePreviewData.error('未选择设备');
      });
      return;
    }

    setState(() {
      _loading = true;
      _data = null;
    });

    final data = await widget.state.adb.readFilePreview(
      serial,
      widget.entry,
      runAsPackage: widget.runAsPackage,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = data;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, entry),
            Divider(height: 1, color: AppColors.borderSoft),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FileEntry entry) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
      child: Row(
        children: [
          Icon(_iconFor(entry.kind), size: 20, color: AppColors.accentBright),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.sizeLabel} · ${entry.modified}',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: Icon(Icons.refresh, color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accentBright),
            const SizedBox(height: 16),
            Text('正在加载…', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final data = _data!;
    return switch (data.kind) {
      FilePreviewKind.text => _TextPreview(data: data, entry: widget.entry),
      FilePreviewKind.image => _ImagePreview(bytes: data.bytes!),
      FilePreviewKind.tooLarge => _MessagePreview(
          icon: Icons.file_download_outlined,
          title: data.error ?? '文件过大',
          message:
              '文件大小 ${_formatBytes(data.actualBytes ?? 0)}，超过预览上限 ${_formatBytes(data.maxBytes ?? 0)}。请使用下载功能查看完整内容。',
        ),
      FilePreviewKind.unsupported => const _MessagePreview(
          icon: Icons.insert_drive_file_outlined,
          title: '暂不支持预览',
          message: '此文件类型无法在应用内预览，请下载后使用本地程序打开。',
        ),
      FilePreviewKind.error => _MessagePreview(
          icon: Icons.error_outline,
          title: '无法预览',
          message: data.error ?? '读取失败',
          actionLabel: '重试',
          onAction: _load,
        ),
    };
  }

  IconData _iconFor(FileKind kind) {
    return switch (kind) {
      FileKind.folder => Icons.folder,
      FileKind.image => Icons.image_outlined,
      FileKind.apk => Icons.android,
      FileKind.text => Icons.description_outlined,
      FileKind.log => Icons.receipt_long_outlined,
      FileKind.json => Icons.data_object_outlined,
      FileKind.other => Icons.insert_drive_file_outlined,
    };
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.data, required this.entry});

  final FilePreviewData data;
  final FileEntry entry;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  final ScrollController _scroll = ScrollController();

  FilePreviewData get data => widget.data;
  bool get isLog => widget.entry.kind == FileKind.log;
  bool get isJson => widget.entry.kind == FileKind.json;

  @override
  void initState() {
    super.initState();
    if (isLog || data.fromTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  String get _truncateHint {
    if (data.fromTail) {
      return '日志较大，仅显示末尾 ${AdbService.previewLogMaxBytes ~/ (1024 * 1024)} MB';
    }
    if (isLog) {
      return '内容已截断（仅显示前 ${AdbService.previewLogMaxBytes ~/ (1024 * 1024)} MB）';
    }
    if (isJson) {
      return '内容已截断（仅显示前 ${AdbService.previewJsonMaxBytes ~/ 1024} KB）';
    }
    return '内容已截断（仅显示前 ${AdbService.previewTextMaxBytes ~/ 1024} KB）';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.truncated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.accent.withValues(alpha: 0.15),
            child: Text(
              _truncateHint,
              style: TextStyle(fontSize: 12, color: AppColors.accentOn),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                data.text ?? '',
                style: TextStyle(
                  fontFamily: 'Consolas',
                  fontSize: isLog ? 12 : 13,
                  height: isJson ? 1.5 : 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 6,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return _MessagePreview(
              icon: Icons.broken_image_outlined,
              title: '无法显示图片',
              message: '图片数据无效或格式不受支持。',
            );
          },
        ),
      ),
    );
  }
}

class _MessagePreview extends StatelessWidget {
  const _MessagePreview({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
