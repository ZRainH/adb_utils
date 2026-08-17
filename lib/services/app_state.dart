import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
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
    this.downloadUrl,
    this.assetName,
    this.assetSize = 0,
    this.releaseNotes = '',
  });

  final String latestTag;
  final String url;
  final bool hasUpdate;
  final String? downloadUrl;
  final String? assetName;
  final int assetSize;
  final String releaseNotes;

  String get sizeLabel {
    if (assetSize <= 0) return '';
    final mb = assetSize / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
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
  bool updateDownloadInProgress = false;
  double updateDownloadProgress = 0;
  String? updateDownloadPath;
  String? updateDownloadError;
  Timer? _pollTimer;
  bool _refreshingDevices = false;

  static const appVersion = '1.0.2';
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
    unawaited(_cleanupOldUpdateExtracts());
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

  Future<void> _cleanupOldUpdateExtracts() async {
    try {
      final root =
          '${settings.effectiveSaveDirectory}${Platform.pathSeparator}updates';
      _tryDeleteOldExtracts(root);
    } catch (_) {}
  }

  /// Best-effort cleanup. Locked folders (running updater) are skipped.
  void _tryDeleteOldExtracts(String updatesDir, {String? keepPath}) {
    try {
      final root = Directory(updatesDir);
      if (!root.existsSync()) return;
      for (final entity in root.listSync()) {
        if (entity is! Directory) continue;
        if (keepPath != null && _samePath(entity.path, keepPath)) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith('extract_')) continue;
        try {
          entity.deleteSync(recursive: true);
        } catch (e) {
          debugPrint('[更新清理] 跳过占用中的目录 ${entity.path}: $e');
        }
      }
    } catch (_) {}
  }

  bool _samePath(String a, String b) {
    final na = a.replaceAll('/', r'\').toLowerCase();
    final nb = b.replaceAll('/', r'\').toLowerCase();
    return na == nb;
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
    _pollTimer = null;
    final secs = settings.devicePollSeconds <= 0 ? 2 : settings.devicePollSeconds;
    try {
      _pollTimer = Timer.periodic(Duration(seconds: secs), (_) {
        unawaited(refreshDevices(quiet: true));
      });
    } catch (e, st) {
      debugPrint('[设备轮询] 启动失败: $e\n$st');
    }
  }

  /// Update poll interval without rebuilding the whole app (avoids Windows crashes).
  Future<void> setDevicePollSeconds(int seconds) async {
    final next = seconds <= 0 ? 2 : seconds;
    if (settings.devicePollSeconds == next) return;
    settings.devicePollSeconds = next;
    _syncPollTimer();
    try {
      await SettingsStore.instance.save(settings);
    } catch (e) {
      debugPrint('[设置] 保存轮询失败: $e');
    }
  }

  Future<void> _enrichDevices() async {
    try {
      final full = await adb.listDevices(enrich: true);
      if (full.isEmpty) return;
      final byId = {for (final d in full) d.id: d};
      final next = [for (final d in devices) byId[d.id] ?? d];
      final same = next.length == devices.length &&
          List.generate(
            next.length,
            (i) =>
                next[i].id == devices[i].id &&
                next[i].name == devices[i].name &&
                next[i].battery == devices[i].battery,
          ).every((e) => e);
      if (same) return;
      devices = next;
      if (selectedDevice != null) {
        selectedDevice = byId[selectedDevice!.id] ?? selectedDevice;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[设备信息] 补充失败: $e');
    }
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

  Future<void> refreshDevices({bool quiet = false}) async {
    if (_refreshingDevices) return;
    _refreshingDevices = true;
    var changed = !quiet;
    if (!quiet) {
      loadingDevices = true;
      lastError = null;
      notifyListeners();
    }
    try {
      adbAvailable = await adb.isAvailable();
      if (!adbAvailable) {
        changed = devices.isNotEmpty || selectedDevice != null;
        devices = const [];
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = '未检测到 adb。请在设置中指定 platform-tools 路径。';
        return;
      }

      final previousIds = devices.map((d) => d.id).toSet();
      final listed = await adb.listDevices(enrich: !quiet);
      if (quiet) {
        final byId = {for (final d in devices) d.id: d};
        devices = [
          for (final d in listed)
            byId[d.id]?.copyWith(connection: d.connection) ?? d,
        ];
      } else {
        devices = listed;
      }
      changed = previousIds.length != devices.length ||
          !previousIds.containsAll(devices.map((d) => d.id));

      if (devices.isEmpty) {
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = '未连接设备。请开启 USB 调试并授权本机。';
      } else {
        lastError = null;
        DeviceInfo? next;
        if (settings.rememberLastDevice && settings.lastDeviceId.isNotEmpty) {
          final remembered =
              devices.where((d) => d.id == settings.lastDeviceId).toList();
          if (remembered.isNotEmpty) next = remembered.first;
        }
        if (next == null && selectedDevice != null) {
          final still =
              devices.where((d) => d.id == selectedDevice!.id).toList();
          if (still.isNotEmpty) next = still.first;
        }
        if (next == null && settings.autoSelectOnConnect) {
          next = devices.first;
        }
        final prevId = selectedDevice?.id;
        selectedDevice = next ?? devices.first;
        if (prevId != selectedDevice?.id) changed = true;
        if (settings.rememberLastDevice) {
          settings.lastDeviceId = selectedDevice!.id;
          unawaited(SettingsStore.instance.save(settings));
        }
      }

      if (quiet && changed) {
        unawaited(_enrichDevices());
      }
      if (selectedDevice != null && (!quiet || changed)) {
        await Future.wait([refreshMetrics(), refreshDeviceFlags()]);
      }
    } catch (e) {
      if (!quiet) {
        changed = true;
        devices = const [];
        selectedDevice = null;
        storage = StorageMetrics.empty;
        memory = MemoryMetrics.empty;
        lastError = e.toString();
      } else {
        debugPrint('[设备轮询] $e');
      }
    } finally {
      _refreshingDevices = false;
      if (!quiet) loadingDevices = false;
      // Quiet polls only rebuild UI when the device set actually changed.
      if (!quiet || changed) {
        notifyListeners();
      }
    }
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
    filesTargetPath = '/storage/emulated/0/Android/data/$pkg';
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
      final notes = (json['body'] as String? ?? '').trim();
      if (tag.isEmpty) {
        debugPrint('[更新检查] tag_name 为空');
        return;
      }

      String? downloadUrl;
      String? assetName;
      var assetSize = 0;
      final assets = json['assets'];
      if (assets is List) {
        Map<String, dynamic>? preferred;
        Map<String, dynamic>? anyZip;
        for (final raw in assets) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final name = (map['name'] as String? ?? '').toLowerCase();
          if (!name.endsWith('.zip')) continue;
          anyZip ??= map;
          if (name.contains('windows')) {
            preferred = map;
            break;
          }
        }
        final chosen = preferred ?? anyZip;
        if (chosen != null) {
          downloadUrl = chosen['browser_download_url'] as String?;
          assetName = chosen['name'] as String?;
          assetSize = (chosen['size'] as num?)?.toInt() ?? 0;
        }
      }

      final latest = tag.replaceFirst(RegExp(r'^v'), '');
      final hasUpdate = _isNewer(latest, appVersion);
      debugPrint(
        '[更新检查] 当前=$appVersion 最新=$tag hasUpdate=$hasUpdate '
        'download=${downloadUrl ?? "(无)"}',
      );
      updateInfo = UpdateInfo(
        latestTag: tag,
        url: htmlUrl,
        hasUpdate: hasUpdate,
        downloadUrl: downloadUrl,
        assetName: assetName,
        assetSize: assetSize,
        releaseNotes: notes,
      );
      notifyListeners();
    } catch (e, st) {
      debugPrint('[更新检查] 失败: $e');
      debugPrint('$st');
    }
  }

  /// Downloads the release zip into the configured save directory.
  /// Returns the local file path on success.
  Future<String?> downloadUpdate({
    void Function(double progress)? onProgress,
  }) async {
    final info = updateInfo;
    final downloadUrl = info?.downloadUrl;
    if (info == null || !info.hasUpdate || downloadUrl == null || downloadUrl.isEmpty) {
      updateDownloadError = '没有可下载的安装包';
      notifyListeners();
      return null;
    }

    updateDownloadInProgress = true;
    updateDownloadProgress = 0;
    updateDownloadError = null;
    updateDownloadPath = null;
    notifyListeners();

    final dir = Directory(
      '${settings.effectiveSaveDirectory}${Platform.pathSeparator}updates',
    );
    try {
      dir.createSync(recursive: true);
    } catch (e) {
      updateDownloadInProgress = false;
      updateDownloadError = '无法创建下载目录：$e';
      notifyListeners();
      return null;
    }

    final fileName = info.assetName?.trim().isNotEmpty == true
        ? info.assetName!
        : 'adb_utils-${info.latestTag}.zip';
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    final candidates = _githubDownloadCandidates(downloadUrl);
    Object? lastError;

    for (var i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      final label = i == 0 ? '直连' : '镜像$i';
      debugPrint('[更新下载] 尝试 $label: $url');
      debugPrint('[更新下载] 保存到 $path');
      try {
        final received = await _downloadFile(
          url: url,
          path: path,
          onProgress: (p) {
            updateDownloadProgress = p;
            onProgress?.call(p);
            notifyListeners();
          },
        );
        updateDownloadProgress = 1;
        updateDownloadPath = path;
        updateDownloadInProgress = false;
        debugPrint('[更新下载] 完成($label) $path ($received bytes)');
        notifyListeners();
        return path;
      } catch (e, st) {
        lastError = e;
        debugPrint('[更新下载] $label 失败: $e');
        debugPrint('$st');
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
        updateDownloadProgress = 0;
        notifyListeners();
      }
    }

    updateDownloadInProgress = false;
    updateDownloadError =
        '下载失败（GitHub 网络超时）。已尝试直连与镜像。\n$lastError';
    notifyListeners();
    return null;
  }

  /// Direct GitHub URL first, then public mirrors (helpful in CN networks).
  List<String> _githubDownloadCandidates(String original) {
    const mirrors = <String>[
      'https://gh-proxy.com/',
      'https://ghproxy.net/',
      'https://mirror.ghproxy.com/',
      'https://gh.llkk.cc/',
    ];
    return <String>[
      original,
      for (final mirror in mirrors) '$mirror$original',
    ];
  }

  Future<int> _downloadFile({
    required String url,
    required String path,
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    client.userAgent = 'adb_utils/$appVersion';
    client.connectionTimeout = const Duration(seconds: 45);
    client.idleTimeout = const Duration(seconds: 120);
    client.autoUncompress = true;

    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 60));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HttpException('下载失败 HTTP ${res.statusCode}');
      }

      final total = res.contentLength;
      final file = File(path);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 120))) {
          sink.add(chunk);
          received += chunk.length;
          final p = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          onProgress?.call(p);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received <= 0) {
        throw const HttpException('下载内容为空');
      }
      // Zip local header magic: PK\x03\x04
      final header = await file.openRead(0, 4).first;
      if (header.length < 2 || header[0] != 0x50 || header[1] != 0x4b) {
        throw const HttpException('下载结果不是有效的 zip（可能是镜像错误页）');
      }
      return received;
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads the zip, extracts it, then launches a GUI updater process
  /// (same exe with `--updater`) that copies files with a progress bar.
  ///
  /// [onProgress] receives 0..1 and a short Chinese status label.
  /// Returns `true` when the updater was started (app should exit).
  Future<bool> downloadAndApplyUpdate({
    void Function(double progress, String status)? onProgress,
  }) async {
    void report(double p, String status) {
      updateDownloadProgress = p.clamp(0.0, 1.0);
      onProgress?.call(updateDownloadProgress, status);
      notifyListeners();
    }

    final zipPath = await downloadUpdate(
      onProgress: (p) => report(p * 0.75, '正在下载（含镜像重试）…'),
    );
    if (zipPath == null) return false;

    if (!Platform.isWindows) {
      updateDownloadError = '当前仅支持 Windows 自动覆盖安装';
      notifyListeners();
      return false;
    }

    updateDownloadInProgress = true;
    notifyListeners();

    try {
      report(0.78, '正在解压…');
      final updatesDir = File(zipPath).parent.path;
      final tag = (updateInfo?.latestTag ?? 'latest')
          .replaceAll(RegExp(r'[^\w.\-]'), '_');
      // Unique folder each time — a previous updater may still lock extract_*.
      final extractDir =
          '$updatesDir${Platform.pathSeparator}extract_${tag}_${DateTime.now().millisecondsSinceEpoch}';
      _tryDeleteOldExtracts(updatesDir, keepPath: extractDir);
      Directory(extractDir).createSync(recursive: true);

      await extractFileToDisk(zipPath, extractDir);
      final payloadRoot = _resolveUpdatePayloadRoot(extractDir);
      final payloadExe =
          File('$payloadRoot${Platform.pathSeparator}adb_utils.exe');
      if (!payloadExe.existsSync()) {
        throw StateError('安装包中未找到 adb_utils.exe');
      }

      report(0.92, '启动安装界面…');
      final installDir = File(Platform.resolvedExecutable).parent.path;
      // Run updater from the *extracted* binary so installDir\adb_utils.exe
      // is not locked by the updater process itself.
      final updaterExe =
          '$payloadRoot${Platform.pathSeparator}adb_utils.exe';
      final targetExe =
          '$installDir${Platform.pathSeparator}adb_utils.exe';

      debugPrint('[更新安装] payload=$payloadRoot');
      debugPrint('[更新安装] installDir=$installDir');
      debugPrint('[更新安装] updaterExe=$updaterExe pid=$pid');

      // Do NOT use Process.start(detached) on the Flutter exe itself —
      // on Windows the child often runs without a visible window.
      // `cmd start` / Start-Process creates a normal desktop process.
      await _launchWindowsUpdater(
        updaterExe: updaterExe,
        workingDirectory: payloadRoot,
        waitPid: pid,
        sourceDir: payloadRoot,
        installDir: installDir,
        exePath: targetExe,
      );

      report(1, '即将退出，安装程序将继续…');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      return true;
    } catch (e, st) {
      debugPrint('[更新安装] 失败: $e');
      debugPrint('$st');
      updateDownloadError = e.toString();
      updateDownloadInProgress = false;
      notifyListeners();
      return false;
    }
  }

  /// Launch the GUI updater outside Flutter's process job so its window shows.
  Future<void> _launchWindowsUpdater({
    required String updaterExe,
    required String workingDirectory,
    required int waitPid,
    required String sourceDir,
    required String installDir,
    required String exePath,
  }) async {
    final updaterArgs = [
      '--updater',
      '--pid=$waitPid',
      '--src=$sourceDir',
      '--dst=$installDir',
      '--exe=$exePath',
    ];

    // Prefer PowerShell Start-Process (reliable visible GUI).
    final psExe = updaterExe.replaceAll("'", "''");
    final psWd = workingDirectory.replaceAll("'", "''");
    final psArgs = updaterArgs
        .map((a) => "'${a.replaceAll("'", "''")}'")
        .join(',');
    final ps = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "Start-Process -FilePath '$psExe' -WorkingDirectory '$psWd' "
            "-ArgumentList @($psArgs)",
      ],
    );
    if (ps.exitCode == 0) {
      debugPrint('[更新安装] 已通过 Start-Process 启动安装窗口');
      return;
    }
    debugPrint(
      '[更新安装] Start-Process 失败(${ps.exitCode}): ${ps.stderr}，改用 cmd start',
    );

    // Fallback: cmd start "" "exe" args…
    final cmd = await Process.start(
      'cmd.exe',
      [
        '/c',
        'start',
        '',
        updaterExe,
        ...updaterArgs,
      ],
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.detached,
    );
    // Detached — don't wait forever; give start a moment to spawn.
    unawaited(cmd.exitCode);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  String _resolveUpdatePayloadRoot(String extractDir) {
    final direct =
        File('$extractDir${Platform.pathSeparator}adb_utils.exe');
    if (direct.existsSync()) return extractDir;

    final children = Directory(extractDir).listSync();
    for (final entity in children) {
      if (entity is! Directory) continue;
      final candidate =
          File('${entity.path}${Platform.pathSeparator}adb_utils.exe');
      if (candidate.existsSync()) return entity.path;
    }
    return extractDir;
  }

  void openDownloadedUpdate() {
    final path = updateDownloadPath;
    if (path == null || path.isEmpty) return;
    try {
      if (Platform.isWindows) {
        Process.start('explorer.exe', ['/select,', path]);
      } else {
        openExternalUrl(File(path).parent.path);
      }
    } catch (e) {
      debugPrint('[更新下载] 打开文件夹失败: $e');
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
    final prevTheme = settings.themePref;
    fn(settings);
    if (settings.devicePollSeconds <= 0) {
      settings.devicePollSeconds = 2;
    }
    if (settings.themePref != prevTheme) {
      _applyThemeColors();
    }
    _syncPollTimer();
    await SettingsStore.instance.save(settings);
    // Defer notify: rebuilding while a Dropdown menu is open crashes on Windows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
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
