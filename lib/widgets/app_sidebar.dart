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
    final surface = AppColors.surfaceOf(context);
    final border = AppColors.borderOf(context);
    final accentBright = AppColors.accentBrightOf(context);
    return Container(
      width: 80,
      decoration: BoxDecoration(
        color: surface,
        border: Border(right: BorderSide(color: border)),
      ),
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
            child: Text(
              'A',
              style: TextStyle(
                color: AppColors.accentOn,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ADB',
            style: TextStyle(
              color: accentBright,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _NavTile(
                      item: items[i],
                      selected: i == selectedIndex,
                      onTap: () => onSelect(i),
                    ),
                  ],
                  const Spacer(),
                  _NavTile(
                    item: const SidebarNavItem(
                      icon: Icons.settings_outlined,
                      label: '设置',
                    ),
                    selected: selectedIndex == 6,
                    onTap: () => onSelect(6),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
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
    final chip = AppColors.chipOf(context);
    final accentBright = AppColors.accentBrightOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? chip.withValues(alpha: 0.85) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border(
                    left: BorderSide(color: accentBright, width: 2),
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                item.icon,
                size: 22,
                color: selected ? accentBright : textSecondary,
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
                  color: selected ? textPrimary : textSecondary,
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
