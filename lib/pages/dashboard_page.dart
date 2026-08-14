import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../services/app_state.dart';
import '../theme/app_colors.dart';
import '../widgets/common_widgets.dart';
import '../widgets/empty_state.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.state, this.onOpenShell});

  final AppState state;
  final VoidCallback? onOpenShell;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1152),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '概览',
              style: TextStyle(
                fontSize: 32,
                color: AppColors.textPrimary,
                letterSpacing: 0.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '管理已连接设备、调试设置与系统资源。',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (state.lastError != null && state.devices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                state.lastError!,
                style: const TextStyle(fontSize: 13, color: AppColors.warning),
              ),
            ],
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionButton(
                label: '刷新设备',
                icon: Icons.refresh,
                onPressed: state.loadingDevices ? null : state.refreshDevices,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 960;
                if (!wide) {
                  return Column(
                    children: [
                      _DevicesPanel(state: state, onOpenShell: onOpenShell),
                      const SizedBox(height: 16),
                      _QuickActionsPanel(state: state),
                      const SizedBox(height: 16),
                      _MetricsPanel(state: state),
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 8,
                          child: _DevicesPanel(state: state, onOpenShell: onOpenShell),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _QuickActionsPanel(state: state),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _MetricsPanel(state: state),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({required this.state, this.onOpenShell});

  final AppState state;
  final VoidCallback? onOpenShell;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              const Text(
                '已连接设备',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${state.devices.length} 台在线',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.loadingDevices)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (state.devices.isEmpty)
            EmptyStateView(
              title: state.adbAvailable ? '没有已连接设备' : 'ADB 不可用',
              message: state.lastError ??
                  '请开启 USB 调试，用数据线连接手机，并在手机上点允许调试。',
              actionLabel: '刷新设备',
              onAction: state.refreshDevices,
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: state.devices
                  .map(
                    (d) => SizedBox(
                      width: 320,
                      child: _DeviceCard(
                        device: d,
                        selected: state.selectedDevice?.id == d.id,
                        onSelect: () => state.selectDevice(d),
                        onShell: onOpenShell,
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.onSelect,
    this.onShell,
  });

  final DeviceInfo device;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onShell;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.accentBright.withValues(alpha: 0.4)
                  : AppColors.borderSoft,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: device.isTablet ? AppColors.chip : const Color(0xFF3C4B55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      device.isTablet ? Icons.tablet_mac : Icons.smartphone,
                      size: 20,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          device.shortId,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'Consolas',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (device.connection == ConnectionType.usb)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.accentBright,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const Icon(Icons.wifi, size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        device.connectionLabel,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: device.connection == ConnectionType.usb
                              ? AppColors.accentBright
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.chip, height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.battery_full, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    device.battery == null ? '—' : '${device.battery}%',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  ActionButton(label: '终端', onPressed: onShell),
                  const SizedBox(width: 8),
                  ActionButton(
                    label: '详情',
                    filled: true,
                    onPressed: onSelect,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, size: 18, color: AppColors.accentBright),
              SizedBox(width: 8),
              Text(
                '快捷操作',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ToggleRow(
            title: '无线调试',
            subtitle: '通过 Wi-Fi 使用 ADB',
            value: state.wirelessDebugging,
            onChanged: state.selectedDevice == null
                ? null
                : (v) {
                    state.setWirelessDebugging(v);
                  },
          ),
          _ToggleRow(
            title: '保持唤醒',
            subtitle: '充电时屏幕常亮',
            value: state.stayAwake,
            onChanged: state.selectedDevice == null
                ? null
                : (v) {
                    state.setStayAwake(v);
                  },
          ),
          _ToggleRow(
            title: '显示布局边界',
            subtitle: 'UI 调试边框',
            value: state.showLayoutBounds,
            onChanged: state.selectedDevice == null
                ? null
                : (v) {
                    state.setShowLayoutBounds(v);
                  },
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final deviceName = state.selectedDevice?.name ?? '设备';
    final storage = state.storage;
    final memory = state.memory;

    return PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                state.selectedDevice == null
                    ? '设备指标'
                    : '设备指标（$deviceName）',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (state.selectedDevice == null) ...[
            const SizedBox(height: 16),
            const Text(
              '连接设备后显示存储与内存信息。',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  '内部存储',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                const Spacer(),
                Text(
                  storage.totalGb <= 0
                      ? '—'
                      : '${storage.usedGb.toStringAsFixed(1)}GB / ${storage.totalGb.toStringAsFixed(1)}GB',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: storage.usedRatio,
                minHeight: 8,
                backgroundColor: AppColors.chip,
                color: AppColors.accentBright,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '已用：${storage.usedPercent}%',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const Spacer(),
                Text(
                  '剩余：${storage.freeGb.toStringAsFixed(1)}GB',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.sd_card, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text(
                  '内存（RAM）',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                const Spacer(),
                Text(
                  memory.totalGb <= 0
                      ? '—'
                      : '${memory.usedGb.toStringAsFixed(1)}GB / ${memory.totalGb.toStringAsFixed(1)}GB',
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Flexible(
                      flex: _flex(memory.systemGb),
                      child: Container(color: AppColors.memorySystem),
                    ),
                    Flexible(
                      flex: _flex(memory.appsGb),
                      child: Container(color: AppColors.memoryApps),
                    ),
                    Flexible(
                      flex: _flex(memory.totalGb - memory.usedGb),
                      child: Container(color: AppColors.chip),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _legendDot(AppColors.memorySystem, '系统'),
                const SizedBox(width: 16),
                _legendDot(AppColors.memoryApps, '应用'),
                const Spacer(),
                Text(
                  '已用：${memory.usedPercent}%',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int _flex(double value) => (value * 100).round().clamp(1, 100000);

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

