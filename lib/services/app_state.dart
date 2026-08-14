import 'package:flutter/foundation.dart';

import '../models/device_info.dart';
import 'adb_service.dart';
import 'tool_paths.dart';

class AppState extends ChangeNotifier {
  AppState({AdbService? adbService})
      : adb = adbService ?? AdbService(adbPath: ToolPaths.resolveAdb());

  final AdbService adb;

  int selectedNav = 0;
  List<DeviceInfo> devices = const [];
  DeviceInfo? selectedDevice;
  bool loadingDevices = false;
  bool adbAvailable = false;
  String? lastError;
  String searchQuery = '';
  /// When set, Database Viewer focuses on this package's databases.
  String? dbPackageFilter;

  /// Pending File Explorer navigation (consumed by FileExplorerPage).
  String? filesTargetPath;
  String? filesRunAsPackage;
  int filesNavToken = 0;

  bool wirelessDebugging = false;
  bool stayAwake = false;
  bool showLayoutBounds = false;

  StorageMetrics storage = StorageMetrics.empty;
  MemoryMetrics memory = MemoryMetrics.empty;

  Future<void> init() async {
    adbAvailable = await adb.isAvailable();
    if (!adbAvailable) {
      lastError = '未检测到 adb。请确认应用目录下 platform-tools 已随包安装。';
      notifyListeners();
      return;
    }
    await refreshDevices();
  }

  void setNav(int index) {
    if (selectedNav == index) {
      // Sidebar re-tap on 数据库 clears app filter → show all.
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

  /// Open the app-bound external data dir (removed on uninstall):
  /// `/sdcard/Android/data/<pkg>/` (contains files / cache).
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
        lastError = '未检测到 adb。请确认应用目录下 platform-tools 已随包安装。';
        return;
      }

      devices = await adb.listDevices();
      if (devices.isEmpty) {
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = '未连接设备。请开启 USB 调试并授权本机。';
      } else {
        final stillThere = devices.where((d) => d.id == selectedDevice?.id);
        selectedDevice = stillThere.isNotEmpty ? stillThere.first : devices.first;
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
}
