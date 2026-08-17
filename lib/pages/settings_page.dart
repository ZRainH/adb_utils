import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/update_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _saveDir;
  bool _checkingUpdate = false;

  AppSettings get s => widget.state.settings;

  @override
  void initState() {
    super.initState();
    _saveDir = TextEditingController(text: s.effectiveSaveDirectory);
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _saveDir.dispose();
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  Future<void> _patch(void Function(AppSettings s) fn) async {
    await widget.state.updateSettings(fn);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      children: [
        Text(
          '设置',
          style: TextStyle(
            fontSize: 32,
            color: AppColors.textPrimary,
            letterSpacing: 0.25,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '本机工具偏好。设备调试开关仍在概览页。',
          style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        _section('保存目录', [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _saveDir,
                    decoration: const InputDecoration(
                      hintText: '下载 / 导出 / 截图目录',
                      isDense: true,
                    ),
                    onSubmitted: (v) => _patch((s) => s.saveDirectory = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                ActionButton(
                  label: '保存',
                  filled: true,
                  onPressed: () => _patch((s) => s.saveDirectory = _saveDir.text.trim()),
                ),
              ],
            ),
          ),
          _kv('实际使用', s.effectiveSaveDirectory),
        ]),
        _section('连接行为', [
          _toggle(
            '启动时刷新设备',
            '打开应用后立即扫描 ADB 设备',
            s.autoRefreshOnStartup,
            (v) => _patch((s) => s.autoRefreshOnStartup = v),
          ),
          _toggle(
            '记住上次设备',
            '下次启动优先选中同一台设备',
            s.rememberLastDevice,
            (v) => _patch((s) => s.rememberLastDevice = v),
          ),
          _toggle(
            '接入时自动选中',
            '发现新设备且当前未选中时自动选择',
            s.autoSelectOnConnect,
            (v) => _patch((s) => s.autoSelectOnConnect = v),
          ),
          _pollIntervalPicker(s),
        ]),
        _section('日志与数据库', [
          _dropdown<int>(
            'Logcat 缓冲区',
            s.logcatBufferSize,
            const [(1000, '1000 条'), (3000, '3000 条'), (8000, '8000 条')],
            (v) => _patch((s) => s.logcatBufferSize = v),
          ),
          _dropdown<String?>(
            '默认日志级别',
            s.defaultLogLevel,
            const [
              (null, '全部'),
              ('verbose', 'Verbose'),
              ('debug', 'Debug'),
              ('info', 'Info'),
              ('warning', 'Warning'),
              ('error', 'Error'),
            ],
            (v) => _patch((s) => s.defaultLogLevel = v),
          ),
          _dropdown<DbRefreshPref>(
            '数据库默认刷新',
            s.dbRefreshMode,
            const [
              (DbRefreshPref.off, '关闭'),
              (DbRefreshPref.timed, '定时'),
              (DbRefreshPref.realtime, '实时'),
            ],
            (v) => _patch((s) => s.dbRefreshMode = v),
          ),
          _dropdown<int>(
            '定时间隔',
            s.dbRefreshSeconds,
            const [(2, '2 秒'), (5, '5 秒'), (10, '10 秒'), (30, '30 秒')],
            (v) => _patch((s) => s.dbRefreshSeconds = v),
          ),
          _dropdown<int>(
            '默认 LIMIT',
            s.dbQueryLimit,
            const [(50, '50'), (200, '200'), (500, '500'), (1000, '1000')],
            (v) => _patch((s) => s.dbQueryLimit = v),
          ),
        ]),
        _section('外观与快捷键', [
          _dropdown<AppThemePref>(
            '主题',
            s.themePref,
            const [
              (AppThemePref.system, '跟随系统'),
              (AppThemePref.dark, '深色'),
              (AppThemePref.light, '浅色'),
            ],
            (v) => _patch((s) => s.themePref = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '终端字体大小',
                        style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    Text(
                      s.terminalFontSize.round().toString(),
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    SizedBox(
                      width: 180,
                      child: Slider(
                        min: 11,
                        max: 18,
                        divisions: 7,
                        value: s.terminalFontSize.clamp(11.0, 18.0),
                        onChanged: (v) => widget.state.previewSettings(
                          (s) => s.terminalFontSize = v.roundToDouble(),
                        ),
                        onChangeEnd: (v) => _patch(
                          (s) => s.terminalFontSize = v.roundToDouble(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '12-34  5678  I  adb_utils: 字体预览 Aa',
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: s.terminalFontSize,
                      height: 1.5,
                      color: AppColors.infoLog,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _dropdown<ScreenshotHotkey>(
            '截图快捷键',
            s.screenshotHotkey,
            const [
              (ScreenshotHotkey.f5, 'F5'),
              (ScreenshotHotkey.ctrlShiftS, 'Ctrl + Shift + S'),
            ],
            (v) => _patch((s) => s.screenshotHotkey = v),
          ),
        ]),
        _section('安全', [
          _toggle(
            '危险操作二次确认',
            '卸载应用、删除文件前弹出确认框',
            s.confirmDangerousActions,
            (v) => _patch((s) => s.confirmDangerousActions = v),
          ),
        ]),
        _section('关于', [
          _kv('应用版本', AppState.appVersion),
          _kv('GitHub', 'https://github.com/${AppState.githubRepo}'),
          _kv(
            '更新',
            widget.state.updateInfo == null
                ? '尚未检查'
                : widget.state.updateInfo!.hasUpdate
                    ? '有新版本 ${widget.state.updateInfo!.latestTag}'
                    : '已是最新（${widget.state.updateInfo!.latestTag}）',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                ActionButton(
                  label: _checkingUpdate ? '检查中…' : '检查更新',
                  icon: Icons.system_update_alt,
                  onPressed: _checkingUpdate
                      ? null
                      : () async {
                          setState(() => _checkingUpdate = true);
                          await widget.state.checkForUpdates();
                          if (!mounted) return;
                          setState(() => _checkingUpdate = false);
                          final info = widget.state.updateInfo;
                          if (info == null) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(content: Text('检查更新失败，请稍后重试')),
                            );
                            return;
                          }
                          if (info.hasUpdate) {
                            await showUpdateAvailableDialog(
                              this.context,
                              widget.state,
                            );
                          } else {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('已是最新版本（${info.latestTag}）'),
                              ),
                            );
                          }
                        },
                ),
                const SizedBox(width: 8),
                ActionButton(
                  label: '打开 Release',
                  icon: Icons.open_in_new,
                  onPressed: () => _openUrl(
                    widget.state.updateInfo?.url ??
                        'https://github.com/${AppState.githubRepo}/releases',
                  ),
                ),
                if (widget.state.updateInfo?.hasUpdate == true) ...[
                  const SizedBox(width: 8),
                  ActionButton(
                    label: '下载更新',
                    filled: true,
                    icon: Icons.download,
                    onPressed: () =>
                        showUpdateAvailableDialog(context, widget.state),
                  ),
                ],
              ],
            ),
          ),
          _toggle(
            '启动时检查更新',
            '对照 GitHub Release 最新版本',
            s.checkUpdatesOnStartup,
            (v) => _patch((s) => s.checkUpdatesOnStartup = v),
          ),
        ]),
      ],
    );
  }

  void _openUrl(String url) {
    widget.state.openExternalUrl(url);
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: PanelCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _pollIntervalPicker(AppSettings s) {
    const options = <(int, String)>[
      (2, '2 秒'),
      (5, '5 秒'),
      (10, '10 秒'),
      (30, '30 秒'),
    ];
    final current = s.devicePollSeconds <= 0 ? 2 : s.devicePollSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '设备轮询',
            style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            '自动检测设备插拔。切换间隔不会重建整个窗口。',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.$2),
                  selected: current == option.$1,
                  onSelected: (_) async {
                    await widget.state.setDevicePollSeconds(option.$1);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(subtitle, style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<(T, String)> items,
    ValueChanged<T> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                dropdownColor: AppColors.surfaceElevated,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                items: [
                  for (final item in items)
                    DropdownMenuItem(value: item.$1, child: Text(item.$2)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  // Wait until the menu overlay closes — sync rebuild exits on Windows.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    onChanged(v);
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(k, style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'Consolas',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
