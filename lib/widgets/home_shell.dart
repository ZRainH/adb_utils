import 'package:flutter/material.dart';

import '../pages/app_manager_page.dart';
import '../pages/command_reference_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/database_viewer_page.dart';
import '../pages/file_explorer_page.dart';
import '../pages/terminal_page.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/top_header.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
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
      default:
        return '搜索设备或包名…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final deviceKey = state.selectedDevice?.id ?? 'none';
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  showDatabaseBadge: state.selectedNav == 3,
                ),
                Expanded(
                  // Keep pages alive so App Manager label enrichment isn't cancelled
                  // when switching tabs.
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
                        key: ValueKey('db-$deviceKey'),
                        state: state,
                      ),
                      TerminalPage(
                        key: ValueKey('term-$deviceKey'),
                        state: state,
                      ),
                      CommandReferencePage(state: state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
