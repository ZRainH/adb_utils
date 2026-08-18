import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'common_widgets.dart';

final _placeholderRe = RegExp(r'<[^>]+>|\[[^\]]+\]');

bool commandHasPlaceholders(String command) =>
    _placeholderRe.hasMatch(command) || command.contains('...');

bool commandLooksDangerous(String command) {
  final lower = command.toLowerCase();
  const keys = [
    ' uninstall ',
    ' rm -',
    ' rm ',
    ' erase ',
    ' format ',
    ' reboot ',
    ' remount ',
    ' disable',
    ' pm clear ',
    ' kill-server',
    ' wipe ',
  ];
  for (final key in keys) {
    if (lower.contains(key.trim()) || lower.contains(key)) return true;
  }
  return lower.startsWith('adb uninstall') ||
      lower.contains('shell rm ') ||
      lower.contains('shell pm clear');
}

String prepareHandbookCommand(String template, {String? deviceSerial}) {
  var cmd = template.replaceAll('\n', ' ').trim();
  if (deviceSerial != null && deviceSerial.isNotEmpty) {
    cmd = cmd.replaceAll('<serial>', deviceSerial);
  }
  return cmd;
}

/// Returns an error message, or null if the command can run.
String? validateHandbookCommand(AppState state, String command) {
  final trimmed = command.trim();
  if (trimmed.isEmpty) return '请输入命令';

  if (commandHasPlaceholders(trimmed)) {
    return '请先替换命令中的占位符（如 <package>、<path.apk>）';
  }

  final serial = state.selectedDevice?.id;
  if (state.adb.handbookCommandNeedsDevice(trimmed) && serial == null) {
    final hasSerialInCmd = RegExp(r'-s\s+\S+').hasMatch(trimmed);
    if (!hasSerialInCmd) return '请先在概览页选择设备';
  }

  return null;
}

Future<bool> confirmDangerousHandbookCommand(
  BuildContext context,
  AppState state,
  String command,
) async {
  if (!commandLooksDangerous(command)) return true;
  if (!context.mounted) return false;
  return confirmIfNeeded(
    context,
    needed: state.settings.confirmDangerousActions,
    title: '运行危险命令',
    message: '即将执行：\n$command',
    confirmLabel: '仍要运行',
  );
}
