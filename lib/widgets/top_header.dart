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
    this.showSearch = true,
    this.onScreenshot,
  });

  final AppState state;
  final String searchHint;
  final Widget? trailing;
  final bool showDatabaseBadge;
  final bool showSearch;
  final VoidCallback? onScreenshot;

  @override
  Widget build(BuildContext context) {
    final device = state.selectedDevice;
    final surface = AppColors.surfaceOf(context);
    final border = AppColors.borderOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final accentBright = AppColors.accentBrightOf(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'ADB 桌面工具',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: textPrimary,
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
                border: Border.all(color: accentBright.withValues(alpha: 0.5)),
              ),
              child: Text(
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
                  color: AppColors.chipOf(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentBright,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '已连接：${device.name}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          if (showSearch)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256, minWidth: 120),
              child: TextField(
                onChanged: state.setSearch,
                style: TextStyle(fontSize: 14, color: textPrimary),
                decoration: InputDecoration(
                  hintText: searchHint,
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: textSecondary,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40),
                ),
              ),
            ),
          const SizedBox(width: 4),
          _IconBtn(
            icon: Icons.usb,
            tooltip: '刷新设备',
            onTap: state.refreshDevices,
          ),
          _IconBtn(
            icon: Icons.wifi,
            tooltip: '无线调试',
            onTap: () => state.setWirelessDebugging(!state.wirelessDebugging),
          ),
          if (onScreenshot != null)
            _IconBtn(
              icon: Icons.photo_camera_outlined,
              tooltip: '截图',
              onTap: onScreenshot!,
            ),
          if (trailing != null) ...[
            const SizedBox(width: 4),
            Container(width: 1, height: 24, color: border),
            const SizedBox(width: 8),
            trailing!,
          ] else ...[
            const SizedBox(width: 4),
            Container(width: 1, height: 24, color: border),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
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
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
      splashRadius: 20,
    );
  }
}
