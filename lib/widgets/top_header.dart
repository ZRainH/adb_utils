import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_colors.dart';

class TopHeader extends StatelessWidget {
  const TopHeader({
    super.key,
    required this.state,
    this.searchHint = '搜索设备或包名…',
    this.trailing,
    this.showDatabaseBadge = false,
  });

  final AppState state;
  final String searchHint;
  final Widget? trailing;
  final bool showDatabaseBadge;

  @override
  Widget build(BuildContext context) {
    final device = state.selectedDevice;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'ADB 桌面工具',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: 0.25,
              ),
            ),
          ),
          if (showDatabaseBadge) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.accentBright.withValues(alpha: 0.5)),
              ),
              child: const Text(
                '数据库查看器',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentOn,
                ),
              ),
            ),
          ],
          if (device != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.accentBright,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '已连接：${device.name}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 256, minWidth: 120),
            child: TextField(
              onChanged: state.setSearch,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: searchHint,
                isDense: true,
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _IconBtn(icon: Icons.usb, onTap: state.refreshDevices),
          _IconBtn(
            icon: Icons.wifi,
            onTap: () => state.setWirelessDebugging(!state.wirelessDebugging),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Container(width: 1, height: 24, color: AppColors.border),
            const SizedBox(width: 8),
            trailing!,
          ] else ...[
            const SizedBox(width: 4),
            Container(width: 1, height: 24, color: AppColors.border),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: const Text(
                'M.',
                style: TextStyle(
                  color: AppColors.accentOn,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: AppColors.textSecondary),
      splashRadius: 20,
    );
  }
}
