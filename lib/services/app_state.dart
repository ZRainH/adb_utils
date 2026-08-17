import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/device_info.dart';
import '../theme/app_colors.dart';
import 'adb_service.dart';
import 'app_settings.dart';
import 'tool_paths.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.latestTag,
    required this.url,
    required this.hasUpdate,
  });

  final String latestTag;
  final String url;
  final bool hasUpdate;
}

class AppState extends ChangeNotifier {
  AppState({AdbService? adbService})
      : adb = adbService ??
            AdbService(
              adbPath: ToolPaths.resolveAdbFor(
                mode: AdbPathMode.bundled,
              ),
            );

  AdbService adb;
  AppSettings settings = AppSettings();

  int selectedNav = 0;
  List<DeviceInfo> devices = const [];
  DeviceInfo? selectedDevice;
  bool loadingDevices = false;
  bool adbAvailable = false;
  String? lastError;
  String searchQuery = '';
  String? dbPackageFilter;
  String? filesTargetPath;
  String? filesRunAsPackage;
  int filesNavToken = 0;

  bool wirelessDebugging = false;
  bool stayAwake = false;
  bool showLayoutBounds = false;

  StorageMetrics storage = StorageMetrics.empty;
  MemoryMetrics memory = MemoryMetrics.empty;

  UpdateInfo? updateInfo;
  Timer? _pollTimer;

  static const appVersion = '1.1.0';
  static const githubRepo = 'ZRainH/adb_utils';

  ThemeMode get themeMode => switch (settings.themePref) {
        AppThemePref.system => ThemeMode.system,
        AppThemePref.dark => ThemeMode.dark,
        AppThemePref.light => ThemeMode.light,
      };

  Future<void> init() async {
    settings = await SettingsStore.instance.load();
    settings.adbPathMode = AdbPathMode.bundled;
    _applyThemeColors();
    _recreateAdb();
    adbAvailable = await adb.isAvailable();
    if (!adbAvailable) {
      lastError = '未检测到 adb。请在设置中指定 platform-tools 路径。';
      notifyListeners();
    } else if (settings.autoRefreshOnStartup) {
      await refreshDevices();
    }
    _syncPollTimer();
    if (settings.checkUpdatesOnStartup) {
      unawaited(checkForUpdates());
    }
  }

  void _applyThemeColors() {
    AppColors.applyThemeMode(
      themeMode,
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  void _recreateAdb() {
    adb = AdbService(
      adbPath: ToolPaths.resolveAdbFor(
        mode: settings.adbPathMode,
        customPath: settings.customAdbPath,
      ),
    );
  }

  Future<void> persist() async {
    await SettingsStore.instance.save(settings);
    notifyListeners();
  }

  Future<void> applyAdbPath({
    required AdbPathMode mode,
    String customPath = '',
  }) async {
    settings.adbPathMode = mode;
    settings.customAdbPath = customPath;
    _recreateAdb();
    await persist();
    await refreshDevices();
  }

  void _syncPollTimer() {
    _pollTimer?.cancel();
    final secs = settings.devicePollSeconds;
    if (secs <= 0) return;
    _pollTimer = Timer.periodic(Duration(seconds: secs), (_) {
      unawaited(refreshDevices());
    });
  }

  void setNav(int index) {
    if (selectedNav == index) {
      if (index == 3 && dbPackageFilter != null) {
        dbPackageFilter = null;
        notifyListeners();
      }
      return;
    }
    selectedNav = index;
    if (index == 3) {
      dbPackageFilter = null;
    }
    notifyListeners();
  }

  void setSearch(String value) {
    searchQuery = value;
    notifyListeners();
  }

  void openAppDatabases(String packageName) {
    dbPackageFilter = packageName;
    selectedNav = 3;
    notifyListeners();
  }

  void openAppCacheDir(String packageName) {
    final pkg = packageName.trim();
    if (pkg.isEmpty) return;
    filesTargetPath = '/sdcard/Android/data/$pkg';
    filesRunAsPackage = pkg;
    filesNavToken++;
    selectedNav = 2;
    notifyListeners();
  }

  void clearDbPackageFilter() {
    if (dbPackageFilter == null) return;
    dbPackageFilter = null;
    notifyListeners();
  }

  Future<void> selectDevice(DeviceInfo device) async {
    selectedDevice = device;
    if (settings.rememberLastDevice) {
      settings.lastDeviceId = device.id;
      unawaited(SettingsStore.instance.save(settings));
    }
    notifyListeners();
    await Future.wait([refreshMetrics(), refreshDeviceFlags()]);
  }

  Future<void> refreshDevices() async {
    loadingDevices = true;
    lastError = null;
    notifyListeners();
    try {
      adbAvailable = await adb.isAvailable();
      if (!adbAvailable) {
        devices = const [];
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = '未检测到 adb。请在设置中指定 platform-tools 路径。';
        return;
      }

      devices = await adb.listDevices();
      if (devices.isEmpty) {
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = '未连接设备。请开启 USB 调试并授权本机。';
      } else {
        DeviceInfo? next;
        if (settings.rememberLastDevice && settings.lastDeviceId.isNotEmpty) {
          final remembered =
              devices.where((d) => d.id == settings.lastDeviceId).toList();
          if (remembered.isNotEmpty) next = remembered.first;
        }
        if (next == null && selectedDevice != null) {
          final still = devices.where((d) => d.id == selectedDevice!.id).toList();
          if (still.isNotEmpty) next = still.first;
        }
        if (next == null && settings.autoSelectOnConnect) {
          next = devices.first;
        }
        selectedDevice = next ?? devices.first;
        if (settings.rememberLastDevice) {
          settings.lastDeviceId = selectedDevice!.id;
          unawaited(SettingsStore.instance.save(settings));
        }
      }
    } catch (e) {
      devices = const [];
      selectedDevice = null;
      storage = StorageMetrics.empty;
      memory = MemoryMetrics.empty;
      lastError = e.toString();
    } finally {
      loadingDevices = false;
      notifyListeners();
    }

    if (selectedDevice != null) {
      await Future.wait([refreshMetrics(), refreshDeviceFlags()]);
    }
  }

  Future<void> refreshMetrics() async {
    final id = selectedDevice?.id;
    if (id == null) {
      storage = StorageMetrics.empty;
      memory = MemoryMetrics.empty;
      notifyListeners();
      return;
    }
    final results = await Future.wait([
      adb.storageMetrics(id),
      adb.memoryMetrics(id),
    ]);
    storage = results[0] as StorageMetrics;
    memory = results[1] as MemoryMetrics;
    notifyListeners();
  }

  Future<void> refreshDeviceFlags() async {
    final id = selectedDevice?.id;
    if (id == null) return;
    final flags = await adb.readDeviceFlags(id);
    wirelessDebugging = flags.wirelessDebugging;
    stayAwake = flags.stayAwake;
    showLayoutBounds = flags.showLayoutBounds;
    notifyListeners();
  }

  Future<void> setWirelessDebugging(bool value) async {
    final id = selectedDevice?.id;
    wirelessDebugging = value;
    notifyListeners();
    if (id == null) return;
    final ok = await adb.setWirelessDebugging(id, value);
    if (!ok) {
      lastError = '设置无线调试失败';
      notifyListeners();
    }
  }

  Future<void> setStayAwake(bool value) async {
    final id = selectedDevice?.id;
    stayAwake = value;
    notifyListeners();
    if (id == null) return;
    final ok = await adb.setStayAwake(id, value);
    if (!ok) {
      lastError = '设置保持唤醒失败';
      notifyListeners();
    }
  }

  Future<void> setShowLayoutBounds(bool value) async {
    final id = selectedDevice?.id;
    showLayoutBounds = value;
    notifyListeners();
    if (id == null) return;
    final ok = await adb.setShowLayoutBounds(id, value);
    if (!ok) {
      lastError = '设置布局边界显示失败';
      notifyListeners();
    }
  }

  Future<String?> takeScreenshot() async {
    final result = await captureScreenshot();
    return result.error ?? result.path;
  }

  /// Returns a user-facing message. If starts with path separator or drive, it's saved path.
  Future<({String? error, String? path})> captureScreenshot() async {
    final id = selectedDevice?.id;
    if (id == null) return (error: '未连接设备', path: null);
    final dir = settings.effectiveSaveDirectory;
    try {
      Directory(dir).createSync(recursive: true);
    } catch (_) {}
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$dir${Platform.pathSeparator}screenshot_$stamp.png';
    final err = await adb.captureScreenshot(id, path);
    if (err != null) return (error: err, path: null);
    return (error: null, path: path);
  }

  Future<void> checkForUpdates() async {
    final url =
        'https://api.github.com/repos/$githubRepo/releases/latest';
    debugPrint('[更新检查] GET $url');
    debugPrint('[更新检查] User-Agent: adb_utils/$appVersion');
    try {
      final client = HttpClient();
      client.userAgent = 'adb_utils/$appVersion';
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      debugPrint('[更新检查] status=${res.statusCode}');
      debugPrint('[更新检查] body=${body.length > 500 ? '${body.substring(0, 500)}…' : body}');
      if (res.statusCode != 200) {
        debugPrint('[更新检查] 非 200，结束');
        return;
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final htmlUrl = json['html_url'] as String? ??
          'https://github.com/$githubRepo/releases';
      if (tag.isEmpty) {
        debugPrint('[更新检查] tag_name 为空');
        return;
      }
      final latest = tag.replaceFirst(RegExp(r'^v'), '');
      final hasUpdate = _isNewer(latest, appVersion);
      debugPrint(
        '[更新检查] 当前=$appVersion 最新=$tag hasUpdate=$hasUpdate html_url=$htmlUrl',
      );
      updateInfo = UpdateInfo(
        latestTag: tag,
        url: htmlUrl,
        hasUpdate: hasUpdate,
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('[更新检查] 失败: $e');
      debugPrint('$st');
    }
  }

  bool _isNewer(String latest, String current) {
    List<int> parts(String v) => v
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final a = parts(latest);
    final b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x > y) return true;
      if (x < y) return false;
    }
    return false;
  }

  Future<void> updateSettings(void Function(AppSettings s) fn) async {
    fn(settings);
    _applyThemeColors();
    _syncPollTimer();
    await persist();
  }

  void previewSettings(void Function(AppSettings s) fn) {
    fn(settings);
    _applyThemeColors();
    notifyListeners();
  }

  void openExternalUrl(String url) {
    try {
      if (Platform.isWindows) {
        Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
      } else {
        Process.start('xdg-open', [url]);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
