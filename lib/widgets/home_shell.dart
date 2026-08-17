import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/app_manager_page.dart';
import '../pages/command_reference_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/database_viewer_page.dart';
import '../pages/file_explorer_page.dart';
import '../pages/settings_page.dart';
import '../pages/terminal_page.dart';
import '../services/app_settings.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/top_header.dart';
import '../widgets/update_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  bool _updateNotified = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (mounted) setState(() {});
    _maybeNotifyUpdate();
  }

  void _maybeNotifyUpdate() {
    final info = widget.state.updateInfo;
    if (_updateNotified || info == null || !info.hasUpdate) return;
    _updateNotified = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showUpdateAvailableDialog(context, widget.state);
    });
  }

  String get _searchHint {
    switch (widget.state.selectedNav) {
      case 1:
        return '搜索应用…';
      case 2:
        return '搜索文件…';
      case 3:
        return '搜索表或数据…';
      case 4:
        return '筛选日志 / 包名…';
      case 5:
        return '搜索命令…';
      case 6:
        return '搜索设置…';
      default:
        return '搜索设备或包名…';
    }
  }

  Future<void> _takeScreenshot() async {
    final result = await widget.state.captureScreenshot();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.error ?? '已保存：${result.path}')),
    );
  }

  Map<ShortcutActivator, VoidCallback> get _screenshotBindings {
    switch (widget.state.settings.screenshotHotkey) {
      case ScreenshotHotkey.f5:
        return {
          const SingleActivator(LogicalKeyboardKey.f5): _takeScreenshot,
        };
      case ScreenshotHotkey.ctrlShiftS:
        return {
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
            shift: true,
          ): _takeScreenshot,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final deviceKey = state.selectedDevice?.id ?? 'none';
    final adbKey = state.adb.adbPath;
    final scaffoldBg = AppColors.backgroundOf(context);
    return CallbackShortcuts(
      bindings: _screenshotBindings,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: scaffoldBg,
          body: Row(
            children: [
              AppSidebar(
                selectedIndex: state.selectedNav,
                onSelect: state.setNav,
              ),
              Expanded(
                child: Column(
                  children: [
                    TopHeader(
                      state: state,
                      searchHint: _searchHint,
                      showSearch: state.selectedNav != 6,
                      showDatabaseBadge: state.selectedNav == 3,
                      onScreenshot: _takeScreenshot,
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: state.selectedNav,
                        children: [
                          DashboardPage(
                            state: state,
                            onOpenShell: () => state.setNav(4),
                          ),
                          AppManagerPage(
                            key: ValueKey('apps-$deviceKey'),
                            state: state,
                          ),
                          FileExplorerPage(
                            key: ValueKey('files-$deviceKey'),
                            state: state,
                          ),
                          DatabaseViewerPage(
                            key: ValueKey('db-$deviceKey-$adbKey'),
                            state: state,
                          ),
                          TerminalPage(
                            key: ValueKey('term-$deviceKey-$adbKey'),
                            state: state,
                          ),
                          CommandReferencePage(state: state),
                          SettingsPage(state: state),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
