import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class SidebarNavItem {
  const SidebarNavItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const items = [
    SidebarNavItem(icon: Icons.grid_view_rounded, label: '概览'),
    SidebarNavItem(icon: Icons.apps_rounded, label: '应用'),
    SidebarNavItem(icon: Icons.folder_outlined, label: '文件'),
    SidebarNavItem(icon: Icons.storage_outlined, label: '数据库'),
    SidebarNavItem(icon: Icons.terminal_rounded, label: '终端'),
    SidebarNavItem(icon: Icons.menu_book_outlined, label: '手册'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: AppColors.surfaceDeep,
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'A',
              style: TextStyle(
                color: AppColors.accentOn,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ADB',
            style: TextStyle(
              color: AppColors.accentBright,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return _NavTile(
                  item: item,
                  selected: selected,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
            child: _NavTile(
              item: const SidebarNavItem(
                icon: Icons.settings_outlined,
                label: '设置',
              ),
              selected: false,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('设置功能即将推出')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SidebarNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.chip.withValues(alpha: 0.7) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? const Border(
                    left: BorderSide(color: AppColors.accentBright, width: 2),
                  )
                : null,
          ),
          child: Column(
            children: [
              Icon(
                item.icon,
                size: 22,
                color: selected ? AppColors.accentBright : AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
