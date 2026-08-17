import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_colors.dart';
import 'common_widgets.dart';

/// Shows the update dialog. Returns true if the user started a download.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  AppState state,
) async {
  final info = state.updateInfo;
  if (info == null || !info.hasUpdate) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(state: state, info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.state, required this.info});

  final AppState state;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  String? _error;
  bool _applied = false;

  UpdateInfo get info => widget.info;

  Future<void> _startUpdate() async {
    if (_busy) return;
    if (info.downloadUrl == null || info.downloadUrl!.isEmpty) {
      setState(() => _error = 'Release 中没有 Windows 安装包（.zip）');
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = '准备下载…';
      _error = null;
      _applied = false;
    });

    final ok = await widget.state.downloadAndApplyUpdate(
      onProgress: (p, status) {
        if (mounted) {
          setState(() {
            _progress = p;
            _status = status;
          });
        }
      },
    );

    if (!mounted) return;
    if (ok) {
      setState(() {
        _busy = false;
        _applied = true;
        _progress = 1;
        _status = '正在退出，安装窗口即将打开…';
      });
      // Give the updater process time to appear before we quit.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    }

    setState(() {
      _busy = false;
      _error = widget.state.updateDownloadError ?? '更新失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final notes = info.releaseNotes.trim();
    final size = info.sizeLabel;
    return AlertDialog(
      backgroundColor: AppColors.surfaceElevated,
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '当前版本 ${AppState.appVersion}，最新版本 ${info.latestTag}。',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
            if (size.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '安装包大小：$size',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '更新说明',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _applied
                  ? '主程序即将退出，安装窗口会显示进度并自动重启。'
                  : '将下载并解压安装包，然后打开带进度条的安装窗口覆盖当前目录并自动重启。',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            if (_busy || _applied || _error != null) ...[
              const SizedBox(height: 14),
              if (_busy || _applied)
                LinearProgressIndicator(
                  value: _progress <= 0 ? null : _progress,
                  backgroundColor: AppColors.chip,
                  color: AppColors.accentBright,
                ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _status,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.warning, fontSize: 12),
                ),
                if (widget.state.updateDownloadPath != null) ...[
                  const SizedBox(height: 6),
                ],
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (!_busy && !_applied)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后'),
          ),
        if (!_busy && !_applied)
          ActionButton(
            label: '立即更新',
            filled: true,
            icon: Icons.system_update_alt,
            onPressed: _startUpdate,
          ),
        if (_busy || _applied)
          const TextButton(
            onPressed: null,
            child: Text('请稍候…'),
          ),
        if (_error != null && !_busy) ...[
          if (widget.state.updateDownloadPath != null)
            TextButton(
              onPressed: () => widget.state.openDownloadedUpdate(),
              child: const Text('打开文件夹'),
            ),
          ActionButton(
            label: '重试',
            filled: true,
            onPressed: _startUpdate,
          ),
        ],
      ],
    );
  }
}
