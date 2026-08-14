import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_info.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/empty_state.dart';

class AppManagerPage extends StatefulWidget {
  const AppManagerPage({super.key, required this.state});

  final AppState state;

  @override
  State<AppManagerPage> createState() => _AppManagerPageState();
}

class _AppManagerPageState extends State<AppManagerPage> {
  AppFilter _filter = AppFilter.user;
  List<AppInfo> _apps = const [];
  bool _loading = false;
  bool _resolvingNames = false;
  String? _error;
  String? _hoveredPackage;
  String? _boundSerial;
  int _loadToken = 0;

  String? get _serial => widget.state.selectedDevice?.id;

  @override
  void initState() {
    super.initState();
    _boundSerial = _serial;
    widget.state.addListener(_onState);
    _load();
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
      _load();
      return;
    }
    setState(() {});
  }

  Future<void> _load() async {
    final serial = _serial;
    final token = ++_loadToken;
    if (serial == null) {
      setState(() {
        _apps = const [];
        _loading = false;
        _resolvingNames = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _resolvingNames = false;
      _error = null;
    });
    try {
      final apps = await widget.state.adb.listApps(serial, filter: _filter);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _apps = apps;
        _loading = false;
        _resolvingNames = apps.isNotEmpty;
      });
      // Labels first (visible), then version/size in background.
      await Future.wait([
        _enrichLabels(serial, token),
        _enrichMeta(serial, token),
      ]);
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _apps = const [];
        _loading = false;
        _resolvingNames = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _enrichLabels(String serial, int token) async {
    try {
      await for (final updated
          in widget.state.adb.resolveAppLabels(serial, List.of(_apps))) {
        if (!mounted || token != _loadToken) return;
        setState(() {
          _apps = [
            for (final app in _apps)
              if (app.packageName == updated.packageName)
                app.copyWith(
                  name: updated.name,
                  apkPath: updated.apkPath ?? app.apkPath,
                )
              else
                app,
          ];
        });
      }
    } finally {
      if (mounted && token == _loadToken) {
        setState(() => _resolvingNames = false);
      }
    }
  }

  Future<void> _enrichMeta(String serial, int token) async {
    await for (final updated
        in widget.state.adb.resolveAppMeta(serial, List.of(_apps))) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _apps = [
          for (final app in _apps)
            if (app.packageName == updated.packageName)
              app.copyWith(
                version: updated.version,
                sizeLabel: updated.sizeLabel,
              )
            else
              app,
        ];
      });
    }
  }

  Future<void> _installApk() async {
    final serial = _serial;
    if (serial == null) return;
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('安装 APK'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: r'C:\path\to\app.apk'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return;
    final error = await widget.state.adb.installApk(serial, path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'APK 已安装')),
    );
    if (error == null) _load();
  }

  Future<void> _uninstall(AppInfo app) async {
    final serial = _serial;
    if (serial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('卸载应用？'),
        content: Text('确定卸载 ${app.packageName}？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('卸载')),
        ],
      ),
    );
    if (ok != true) return;
    final error = await widget.state.adb.uninstallApp(serial, app.packageName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已卸载 ${app.name}')),
    );
    if (error == null) _load();
  }

  Future<void> _launch(AppInfo app) async {
    final serial = _serial;
    if (serial == null) return;
    final error = await widget.state.adb.launchApp(serial, app.packageName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已启动 ${app.packageName}')),
    );
  }

  Future<void> _copyPackageName(AppInfo app) async {
    await Clipboard.setData(ClipboardData(text: app.packageName));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制包名：${app.packageName}')),
    );
  }

  List<AppInfo> get _filtered {
    final q = widget.state.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _apps;
    return _apps
        .where(
          (a) =>
              a.name.toLowerCase().contains(q) ||
              a.packageName.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_serial == null) {
      return EmptyStateView(
        title: '未选择设备',
        message: widget.state.lastError ?? '请先在概览页连接并选择一台设备。',
        actionLabel: '刷新设备',
        onAction: widget.state.refreshDevices,
      );
    }

    final apps = _filtered;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      PillButton(
                        label: '用户应用',
                        selected: _filter == AppFilter.user,
                        onTap: () {
                          setState(() => _filter = AppFilter.user);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: '系统应用',
                        selected: _filter == AppFilter.system,
                        onTap: () {
                          setState(() => _filter = AppFilter.system);
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: '已禁用',
                        selected: _filter == AppFilter.disabled,
                        onTap: () {
                          setState(() => _filter = AppFilter.disabled);
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_resolvingNames) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text(
                  '正在解析应用名称…',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(width: 12),
              ],
              ActionButton(
                label: '刷新',
                icon: Icons.refresh,
                onPressed: _loading ? null : _load,
              ),
              const SizedBox(width: 8),
              ActionButton(
                label: '安装 APK',
                icon: Icons.add,
                primaryLight: true,
                onPressed: _installApk,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: PanelCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E2021),
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('应用名称', style: _headerStyle)),
                        Expanded(flex: 4, child: Text('包名', style: _headerStyle)),
                        Expanded(flex: 2, child: Text('版本', style: _headerStyle)),
                        SizedBox(
                          width: _actionsWidth,
                          child: Text('操作', style: _headerStyle, textAlign: TextAlign.right),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : _error != null
                            ? EmptyStateView(
                                icon: Icons.error_outline,
                                title: '读取应用失败',
                                message: _error!,
                                actionLabel: '重试',
                                onAction: _load,
                              )
                            : apps.isEmpty
                                ? const EmptyStateView(
                                    icon: Icons.apps_outage,
                                    title: '没有应用',
                                    message: '当前筛选条件下未找到已安装应用。',
                                  )
                                : ListView.separated(
                                    itemCount: apps.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      color: AppColors.border,
                                    ),
                                    itemBuilder: (context, index) {
                                      final app = apps[index];
                                      final hovered = _hoveredPackage == app.packageName;
                                      return MouseRegion(
                                        onEnter: (_) =>
                                            setState(() => _hoveredPackage = app.packageName),
                                        onExit: (_) => setState(() => _hoveredPackage = null),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      decoration: BoxDecoration(
                                                        color: AppColors.chip,
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(
                                                        Icons.android,
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Flexible(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            app.name,
                                                            overflow: TextOverflow.ellipsis,
                                                            style: const TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w500,
                                                              color: AppColors.textPrimary,
                                                            ),
                                                          ),
                                                          Text(
                                                            app.sizeLabel,
                                                            style: const TextStyle(
                                                              fontSize: 12,
                                                              color: AppColors.textSecondary,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 4,
                                                child: InkWell(
                                                  onTap: () => _copyPackageName(app),
                                                  borderRadius: BorderRadius.circular(4),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                                    child: Text(
                                                      app.packageName,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        fontFamily: 'Consolas',
                                                        color: AppColors.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  app.version,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontFamily: 'Consolas',
                                                    color: AppColors.textSecondary,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: _actionsWidth,
                                                child: Opacity(
                                                  opacity: hovered ? 1 : 0,
                                                  child: IgnorePointer(
                                                    ignoring: !hovered,
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.end,
                                                      children: [
                                                        _ActionIcon(
                                                          tooltip: '启动',
                                                          icon: Icons.play_arrow,
                                                          onPressed: () => _launch(app),
                                                        ),
                                                        _ActionIcon(
                                                          tooltip: '应用数据目录',
                                                          icon: Icons.folder_open_outlined,
                                                          onPressed: () => widget.state
                                                              .openAppCacheDir(app.packageName),
                                                        ),
                                                        _ActionIcon(
                                                          tooltip: '数据库',
                                                          icon: Icons.storage_outlined,
                                                          onPressed: () => widget.state
                                                              .openAppDatabases(app.packageName),
                                                        ),
                                                        _ActionIcon(
                                                          tooltip: '复制包名',
                                                          icon: Icons.copy_rounded,
                                                          onPressed: () => _copyPackageName(app),
                                                        ),
                                                        _ActionIcon(
                                                          tooltip: '详情',
                                                          icon: Icons.info_outline,
                                                          onPressed: () {
                                                            ScaffoldMessenger.of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                content: Text(
                                                                  '${app.name}\n${app.packageName}\nv${app.version} · ${app.sizeLabel}',
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                        _ActionIcon(
                                                          tooltip: '卸载',
                                                          icon: Icons.delete_outline,
                                                          onPressed: () => _uninstall(app),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}

const _actionsWidth = 210.0;

const _headerStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: AppColors.textSecondary,
  letterSpacing: 0.1,
);

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      splashRadius: 16,
    );
  }
}
