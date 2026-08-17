import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/device_info.dart';
import '../services/adb_service.dart';
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
            Text(
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
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (state.lastError != null && state.devices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                state.lastError!,
                style: TextStyle(fontSize: 13, color: AppColors.warning),
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
              Icon(Icons.phone_android, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
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
                  style: TextStyle(
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
                        state: state,
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
    required this.state,
    this.onShell,
  });

  final DeviceInfo device;
  final bool selected;
  final VoidCallback onSelect;
  final AppState state;
  final VoidCallback? onShell;

  Future<void> _showDetails(BuildContext context) async {
    onSelect();
    await showDialog<void>(
      context: context,
      builder: (context) => _DeviceDetailsDialog(
        device: device,
        adb: state.adb,
      ),
    );
  }

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
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          device.shortId,
                          style: TextStyle(
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
                          decoration: BoxDecoration(
                            color: AppColors.accentBright,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        Icon(Icons.wifi, size: 14, color: AppColors.textMuted),
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
              Divider(color: AppColors.chip, height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.battery_full, size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    device.battery == null ? '—' : '${device.battery}%',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  ActionButton(label: '终端', onPressed: onShell),
                  const SizedBox(width: 8),
                  ActionButton(
                    label: '详情',
                    filled: true,
                    onPressed: () => _showDetails(context),
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
          Row(
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
              Icon(Icons.memory, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                state.selectedDevice == null
                    ? '设备指标'
                    : '设备指标（$deviceName）',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (state.selectedDevice == null) ...[
            const SizedBox(height: 16),
            Text(
              '连接设备后显示存储与内存信息。',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '内部存储',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                const Spacer(),
                Text(
                  storage.totalGb <= 0
                      ? '—'
                      : '${storage.usedGb.toStringAsFixed(1)}GB / ${storage.totalGb.toStringAsFixed(1)}GB',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const Spacer(),
                Text(
                  '剩余：${storage.freeGb.toStringAsFixed(1)}GB',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.sd_card, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  '内存（RAM）',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
                const Spacer(),
                Text(
                  memory.totalGb <= 0
                      ? '—'
                      : '${memory.usedGb.toStringAsFixed(1)}GB / ${memory.totalGb.toStringAsFixed(1)}GB',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
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
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _DeviceDetailsDialog extends StatefulWidget {
  const _DeviceDetailsDialog({
    required this.device,
    required this.adb,
  });

  final DeviceInfo device;
  final AdbService adb;

  @override
  State<_DeviceDetailsDialog> createState() => _DeviceDetailsDialogState();
}

class _DeviceDetailsDialogState extends State<_DeviceDetailsDialog> {
  DeviceDetails? _details;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final details = await widget.adb.fetchDeviceDetails(widget.device.id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyAll() async {
    final d = _details;
    if (d == null) return;
    final lines = <String>[
      '设备：${d.displayTitle}',
      'ADB ID：${widget.device.id}',
      if (d.brand != null) '品牌：${d.brand}',
      if (d.manufacturer != null) '厂商：${d.manufacturer}',
      if (d.model != null) '型号：${d.model}',
      if (d.androidVersion != null)
        'Android：${d.androidVersion} (SDK ${d.sdkInt ?? "—"})',
      if (d.securityPatch != null) '安全补丁：${d.securityPatch}',
      if (d.buildId != null) 'Build：${d.buildId}',
      if (d.abi != null) 'ABI：${d.abi}',
      if (d.screenSize != null) '分辨率：${d.screenSize}',
      if (d.screenDensity != null) '密度：${d.screenDensity} dpi',
      if (d.batteryLevel != null)
        '电量：${d.batteryLevel}% (${d.batteryStatus ?? "—"})',
      if (d.ipAddress != null) 'IP：${d.ipAddress}',
      if (d.wifiSsid != null) 'Wi-Fi：${d.wifiSsid}',
      if (d.serialNo != null) '序列号：${d.serialNo}',
      if (d.androidId != null) 'Android ID：${d.androidId}',
      if (d.uptime != null) '运行时间：${d.uptime}',
      if (d.fingerprint != null) 'Fingerprint：${d.fingerprint}',
    ];
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('设备详情已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    return Dialog(
      backgroundColor: AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(
                    widget.device.isTablet ? Icons.tablet_mac : Icons.smartphone,
                    color: AppColors.accentBright,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d?.displayTitle ?? widget.device.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          widget.device.id,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Consolas',
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                  IconButton(
                    tooltip: '复制',
                    onPressed: d == null ? null : _copyAll,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: EmptyStateView(
                            icon: Icons.error_outline,
                            title: '读取详情失败',
                            message: _error!,
                            actionLabel: '重试',
                            onAction: _load,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                          children: [
                            _section('基本信息', [
                              _row('连接方式', widget.device.connectionLabel),
                              _row('品牌', d?.brand),
                              _row('厂商', d?.manufacturer),
                              _row('型号', d?.model),
                              _row('设备代号', d?.device),
                              _row('市场名称', d?.marketName),
                              _row('硬件', d?.hardware),
                              _row('主板', d?.board),
                              _row('序列号', d?.serialNo),
                              _row('Android ID', d?.androidId),
                            ]),
                            _section('系统', [
                              _row(
                                'Android',
                                d?.androidVersion == null
                                    ? null
                                    : '${d!.androidVersion}（API ${d.sdkInt ?? "—"}）',
                              ),
                              _row('安全补丁', d?.securityPatch),
                              _row('Build ID', d?.buildId),
                              _row('ABI', d?.abi),
                              _row('ABI 列表', d?.abis),
                              _row('语言', d?.locale),
                              _row('时区', d?.timezone),
                              _row('运行时间', d?.uptime),
                              _row('Fingerprint', d?.fingerprint, mono: true),
                            ]),
                            _section('显示', [
                              _row('分辨率', d?.screenSize),
                              _row(
                                '密度',
                                d?.screenDensity == null
                                    ? null
                                    : '${d!.screenDensity} dpi',
                              ),
                            ]),
                            _section('电池', [
                              _row(
                                '电量',
                                d?.batteryLevel == null ? null : '${d!.batteryLevel}%',
                              ),
                              _row('状态', d?.batteryStatus),
                              _row('健康', d?.batteryHealth),
                              _row(
                                '温度',
                                d?.batteryTempC == null
                                    ? null
                                    : '${d!.batteryTempC!.toStringAsFixed(1)} ℃',
                              ),
                              _row(
                                '电压',
                                d?.batteryVoltageMv == null
                                    ? null
                                    : '${d!.batteryVoltageMv} mV',
                              ),
                              _row(
                                '供电',
                                _powerLabel(d),
                              ),
                            ]),
                            _section('网络', [
                              _row('IP', d?.ipAddress),
                              _row('Wi-Fi', d?.wifiSsid),
                            ]),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String? _powerLabel(DeviceDetails? d) {
    if (d == null) return null;
    final parts = <String>[
      if (d.acPowered == true) 'AC',
      if (d.usbPowered == true) 'USB',
      if (d.wirelessPowered == true) '无线充电',
    ];
    if (parts.isEmpty) return '未接电源';
    return parts.join(' / ');
  }

  Widget _section(String title, List<Widget> rows) {
    final children = rows.where((w) {
      if (w is _DetailRow) {
        return w.value != null && w.value!.trim().isNotEmpty;
      }
      return true;
    }).toList();
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.accentBright,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, color: AppColors.borderSoft),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String? value, {bool mono = false}) {
    return _DetailRow(label: label, value: value, mono: mono);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String? value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final text = (value == null || value!.trim().isEmpty) ? '—' : value!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              text,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'Consolas' : null,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ),
          if (value != null && value!.trim().isNotEmpty)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制 $label')),
                );
              },
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded, size: 14, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

