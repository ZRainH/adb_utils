import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_info.dart';
import '../models/device_info.dart';
import '../models/file_entry.dart';
import '../models/log_entry.dart';
import 'apk_label_parser.dart';

class StorageMetrics {
  const StorageMetrics({
    required this.usedGb,
    required this.totalGb,
  });

  static const empty = StorageMetrics(usedGb: 0, totalGb: 0);

  final double usedGb;
  final double totalGb;

  double get usedRatio => totalGb <= 0 ? 0 : (usedGb / totalGb).clamp(0.0, 1.0);
  double get freeGb => (totalGb - usedGb).clamp(0, totalGb);
  int get usedPercent => (usedRatio * 100).round();
}

class MemoryMetrics {
  const MemoryMetrics({
    required this.systemGb,
    required this.appsGb,
    required this.totalGb,
  });

  static const empty = MemoryMetrics(systemGb: 0, appsGb: 0, totalGb: 0);

  final double systemGb;
  final double appsGb;
  final double totalGb;

  double get usedGb => systemGb + appsGb;
  double get usedRatio => totalGb <= 0 ? 0 : (usedGb / totalGb).clamp(0.0, 1.0);
  int get usedPercent => (usedRatio * 100).round();
}

class AdbException implements Exception {
  AdbException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AdbService {
  AdbService({this.adbPath = 'adb'});

  final String adbPath;
  Process? _logcatProcess;

  Future<ProcessResult> _run(
    List<String> args, {
    String? serial,
    Duration? timeout,
  }) async {
    final full = <String>[
      if (serial != null) ...['-s', serial],
      ...args,
    ];
    try {
      return await Process.run(adbPath, full).timeout(
        timeout ?? const Duration(seconds: 30),
      );
    } on TimeoutException {
      throw AdbException('ADB 命令超时：adb ${full.join(' ')}');
    } on ProcessException catch (e) {
      throw AdbException('无法运行 adb：${e.message}');
    }
  }

  Future<String> shell(String serial, String command, {Duration? timeout}) =>
      _shell(serial, command, timeout: timeout);

  Future<Uint8List?> execOutBytes(
    String serial,
    List<String> remoteArgs, {
    int maxBytes = 64 * 1024 * 1024,
  }) =>
      _execOutBytes(serial, remoteArgs, maxBytes: maxBytes);

  Future<String> _shell(String serial, String command, {Duration? timeout}) async {
    final result = await _run(
      ['shell', command],
      serial: serial,
      timeout: timeout,
    );
    final out = result.stdout.toString();
    final err = result.stderr.toString().trim();
    if (result.exitCode != 0 && out.trim().isEmpty) {
      throw AdbException(err.isEmpty ? 'shell failed ($command)' : err);
    }
    return out;
  }

  Future<bool> isAvailable() async {
    try {
      final result = await _run(['version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<List<DeviceInfo>> listDevices({bool enrich = true}) async {
    final result = await _run(['devices', '-l']);
    if (result.exitCode != 0) {
      throw AdbException(
        result.stderr.toString().trim().isEmpty
            ? 'adb devices failed'
            : result.stderr.toString().trim(),
      );
    }

    final lines = const LineSplitter()
        .convert(result.stdout.toString())
        .skip(1)
        .where((l) => l.trim().isNotEmpty);

    final devices = <DeviceInfo>[];
    for (final line in lines) {
      final parsed = _parseDevicesLine(line);
      if (parsed == null) continue;
      if (!enrich) {
        devices.add(parsed);
        continue;
      }

      final battery = await _readBattery(parsed.id);
      final props = await _readDeviceProps(parsed.id);
      devices.add(
        parsed.copyWith(
          name: props['ro.product.model'] ?? parsed.name,
          model: props['ro.product.model'] ?? parsed.model,
          battery: battery,
          isTablet: _looksLikeTablet(
            props['ro.build.characteristics'] ?? '',
            props['ro.product.model'] ?? parsed.name,
          ),
        ),
      );
    }
    return devices;
  }

  DeviceInfo? _parseDevicesLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final id = parts[0];
    final state = parts[1];
    if (state != 'device') return null;

    String? model;
    String? product;
    String? deviceName;
    for (final p in parts.skip(2)) {
      if (p.startsWith('model:')) model = p.substring(6).replaceAll('_', ' ');
      if (p.startsWith('product:')) product = p.substring(8);
      if (p.startsWith('device:')) deviceName = p.substring(7);
    }

    final displayName = model ?? product ?? deviceName ?? id;
    final isTcp = id.contains(':') && RegExp(r'^\d').hasMatch(id);
    return DeviceInfo(
      id: id,
      name: displayName,
      model: model,
      connection: isTcp ? ConnectionType.tcpip : ConnectionType.usb,
    );
  }

  bool _looksLikeTablet(String characteristics, String model) {
    final c = characteristics.toLowerCase();
    final m = model.toLowerCase();
    return c.contains('tablet') || m.contains('tab') || m.contains('pad');
  }

  Future<Map<String, String>> _readDeviceProps(String serial) async {
    try {
      final out = await _shell(
        serial,
        'getprop ro.product.model; getprop ro.build.characteristics',
      );
      final lines = const LineSplitter().convert(out.trim());
      return {
        if (lines.isNotEmpty) 'ro.product.model': lines[0].trim(),
        if (lines.length > 1) 'ro.build.characteristics': lines[1].trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  Future<int?> _readBattery(String serial) async {
    try {
      final out = await _shell(serial, 'dumpsys battery');
      final match = RegExp(r'level:\s*(\d+)').firstMatch(out);
      return match == null ? null : int.tryParse(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  /// Full device profile for the details dialog.
  Future<DeviceDetails> fetchDeviceDetails(String serial) async {
    final props = await _shell(
      serial,
      [
        'echo PROP',
        'getprop ro.product.brand',
        'getprop ro.product.manufacturer',
        'getprop ro.product.model',
        'getprop ro.product.device',
        'getprop ro.product.name',
        'getprop ro.build.version.release',
        'getprop ro.build.version.sdk',
        'getprop ro.build.version.security_patch',
        'getprop ro.build.display.id',
        'getprop ro.build.fingerprint',
        'getprop ro.product.cpu.abi',
        'getprop ro.product.cpu.abilist',
        'getprop ro.serialno',
        'getprop ro.hardware',
        'getprop ro.product.board',
        'getprop persist.sys.locale',
        'getprop persist.sys.timezone',
        'settings get secure android_id',
        'echo SCREEN',
        'wm size',
        'wm density',
        'echo BATTERY',
        'dumpsys battery',
        'echo NET',
        'ip -f inet addr show wlan0 2>/dev/null || ip -f inet addr show eth0 2>/dev/null || true',
        'dumpsys wifi 2>/dev/null | grep -m1 "mWifiInfo\\|SSID:" || true',
        'echo UPTIME',
        'cat /proc/uptime',
      ].join('; '),
      timeout: const Duration(seconds: 20),
    );

    final sections = _splitSections(props, const [
      'PROP',
      'SCREEN',
      'BATTERY',
      'NET',
      'UPTIME',
    ]);

    final propLines = const LineSplitter()
        .convert(sections['PROP'] ?? '')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    String? propAt(int i) {
      if (i < 0 || i >= propLines.length) return null;
      final v = propLines[i].trim();
      if (v.isEmpty || v == 'null' || v == '[null]') return null;
      return v;
    }

    final screen = sections['SCREEN'] ?? '';
    final sizeMatch = RegExp(r'Physical size:\s*(\S+)').firstMatch(screen);
    final densityMatch = RegExp(r'Physical density:\s*(\S+)').firstMatch(screen);

    final batteryText = sections['BATTERY'] ?? '';
    int? batInt(String key) {
      final m = RegExp('$key:\\s*(-?\\d+)').firstMatch(batteryText);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    String? batStatus() {
      final code = batInt('status');
      return switch (code) {
        1 => '未知',
        2 => '充电中',
        3 => '放电中',
        4 => '未充电',
        5 => '已充满',
        _ => code?.toString(),
      };
    }

    String? batHealth() {
      final code = batInt('health');
      return switch (code) {
        1 => '未知',
        2 => '良好',
        3 => '过热',
        4 => '损坏',
        5 => '过压',
        6 => '未知故障',
        7 => '过冷',
        _ => code?.toString(),
      };
    }

    final tempTenths = batInt('temperature');
    final net = sections['NET'] ?? '';
    final ipMatch = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(net);
    var ssid = RegExp(r'SSID:\s*([^,\n\]]+)').firstMatch(net)?.group(1)?.trim();
    if (ssid != null) {
      ssid = ssid.replaceAll('"', '').trim();
      if (ssid == '<unknown ssid>' || ssid.isEmpty) ssid = null;
    }

    final uptimeParts = (sections['UPTIME'] ?? '').trim().split(RegExp(r'\s+'));
    final uptimeRaw = uptimeParts.isEmpty ? null : uptimeParts.first;
    final uptimeSecs = double.tryParse(uptimeRaw ?? '');
    String? uptimeLabel;
    if (uptimeSecs != null) {
      final total = uptimeSecs.floor();
      final d = total ~/ 86400;
      final h = (total % 86400) ~/ 3600;
      final m = (total % 3600) ~/ 60;
      uptimeLabel = [
        if (d > 0) '$d 天',
        if (h > 0 || d > 0) '$h 小时',
        '$m 分钟',
      ].join(' ');
    }

    return DeviceDetails(
      brand: propAt(0),
      manufacturer: propAt(1),
      model: propAt(2),
      device: propAt(3),
      marketName: propAt(4),
      androidVersion: propAt(5),
      sdkInt: propAt(6),
      securityPatch: propAt(7),
      buildId: propAt(8),
      fingerprint: propAt(9),
      abi: propAt(10),
      abis: propAt(11),
      serialNo: propAt(12),
      hardware: propAt(13),
      board: propAt(14),
      locale: propAt(15),
      timezone: propAt(16),
      androidId: propAt(17),
      screenSize: sizeMatch?.group(1),
      screenDensity: densityMatch?.group(1),
      batteryLevel: batInt('level'),
      batteryStatus: batStatus(),
      batteryHealth: batHealth(),
      batteryTempC: tempTenths == null ? null : tempTenths / 10.0,
      batteryVoltageMv: batInt('voltage'),
      acPowered: batteryText.contains('AC powered: true'),
      usbPowered: batteryText.contains('USB powered: true'),
      wirelessPowered: batteryText.contains('Wireless powered: true'),
      ipAddress: ipMatch?.group(1),
      wifiSsid: ssid,
      uptime: uptimeLabel,
    );
  }

  Map<String, String> _splitSections(String text, List<String> markers) {
    final result = <String, String>{};
    final lines = const LineSplitter().convert(text);
    String? current;
    final buffer = StringBuffer();
    void flush() {
      final key = current;
      if (key != null) {
        result[key] = buffer.toString().trim();
        buffer.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (markers.contains(trimmed)) {
        flush();
        current = trimmed;
        continue;
      }
      if (current != null) {
        buffer.writeln(line);
      }
    }
    flush();
    return result;
  }

  Future<List<AppInfo>> listApps(
    String serial, {
    AppFilter filter = AppFilter.user,
  }) async {
    final flag = switch (filter) {
      AppFilter.user => '-3',
      AppFilter.system => '-s',
      AppFilter.disabled => '-d',
    };

    // `pm list packages -f` returns package:/path/base.apk=com.foo in one shot.
    final out = await _shell(serial, 'pm list packages -f $flag');
    final apps = <AppInfo>[];
    for (final line in const LineSplitter().convert(out)) {
      final parsed = _parsePackageFileLine(line);
      if (parsed == null) continue;
      final cached = _labelCache[parsed.packageName];
      apps.add(
        AppInfo(
          name: cached ?? _guessLabel(parsed.packageName),
          packageName: parsed.packageName,
          version: '—',
          sizeLabel: '—',
          filter: filter,
          apkPath: parsed.apkPath,
        ),
      );
    }
    apps.sort((a, b) => a.packageName.compareTo(b.packageName));
    return apps;
  }

  ({String packageName, String apkPath})? _parsePackageFileLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('package:') || !trimmed.contains('=')) return null;
    final body = trimmed.substring(8);
    final eq = body.lastIndexOf('=');
    if (eq <= 0 || eq >= body.length - 1) return null;
    final apkPath = body.substring(0, eq).trim();
    final packageName = body.substring(eq + 1).trim();
    if (apkPath.isEmpty || packageName.isEmpty) return null;
    return (packageName: packageName, apkPath: apkPath);
  }

  /// Resolves real display names from each APK's AndroidManifest / resources.arsc.
  /// Yields updated [AppInfo] as labels are discovered (for progressive UI).
  Stream<AppInfo> resolveAppLabels(String serial, List<AppInfo> apps) async* {
    const concurrency = 2;
    for (var i = 0; i < apps.length; i += concurrency) {
      final end = (i + concurrency > apps.length) ? apps.length : i + concurrency;
      final slice = apps.sublist(i, end);
      final resolved = await Future.wait(
        slice.map((app) => _resolveDisplayName(serial, app)),
      );
      for (final item in resolved) {
        if (item != null) yield item;
      }
    }
  }

  /// Fills version / size after the initial fast package list.
  Stream<AppInfo> resolveAppMeta(String serial, List<AppInfo> apps) async* {
    const concurrency = 6;
    for (var i = 0; i < apps.length; i += concurrency) {
      final end = (i + concurrency > apps.length) ? apps.length : i + concurrency;
      final slice = apps.sublist(i, end);
      final resolved = await Future.wait(slice.map((app) => _resolveMeta(serial, app)));
      for (final item in resolved) {
        if (item != null) yield item;
      }
    }
  }

  Future<AppInfo?> _resolveMeta(String serial, AppInfo app) async {
    try {
      final out = await _shell(
        serial,
        'dumpsys package ${shellQuote(app.packageName)} | grep -m1 versionName',
        timeout: const Duration(seconds: 12),
      );
      final version = RegExp(r'versionName=([^\s]+)').firstMatch(out)?.group(1) ?? '—';
      var sizeLabel = '—';
      final apkPath = app.apkPath;
      if (apkPath != null && apkPath.isNotEmpty) {
        try {
          final sizeOut = await _shell(
            serial,
            'stat -c%s ${shellQuote(apkPath)} || wc -c < ${shellQuote(apkPath)}',
            timeout: const Duration(seconds: 8),
          );
          final size = int.tryParse(sizeOut.trim().split(RegExp(r'\s+')).first) ?? 0;
          if (size > 0) sizeLabel = _formatBytes(size);
        } catch (_) {}
      }
      if (version == app.version && sizeLabel == app.sizeLabel) return null;
      return app.copyWith(version: version, sizeLabel: sizeLabel);
    } catch (_) {
      return null;
    }
  }

  Future<AppInfo?> _resolveDisplayName(String serial, AppInfo app) async {
    final cacheKey = app.packageName;
    final cached = _labelCache[cacheKey];
    if (cached != null) {
      return cached == app.name ? null : app.copyWith(name: cached);
    }

    try {
      final pathOut = await _shell(
        serial,
        'pm path ${shellQuote(app.packageName)}',
        timeout: const Duration(seconds: 10),
      );
      final apkPaths = _allApkPaths(pathOut);
      final baseApk = apkPaths.isNotEmpty
          ? _pickBaseApkPath(pathOut) ?? apkPaths.first
          : app.apkPath;
      if (baseApk == null || baseApk.isEmpty) return null;

      final manifest = await _readApkEntry(serial, baseApk, 'AndroidManifest.xml');
      if (manifest == null || !_looksLikeAxml(manifest)) return null;

      var label = ApkLabelParser.readApplicationLabel(manifest);
      if (label == null) {
        final baseArsc = await _readApkEntry(
          serial,
          baseApk,
          'resources.arsc',
          maxBytes: 24 * 1024 * 1024,
        );
        final localeArscs = <Uint8List>[];
        for (final path in apkPaths) {
          final lower = path.toLowerCase();
          if (!(lower.contains('split_config.zh') ||
              lower.contains('split_config.zh_'))) {
            continue;
          }
          final bytes = await _readApkEntry(
            serial,
            path,
            'resources.arsc',
            maxBytes: 16 * 1024 * 1024,
          );
          if (bytes != null && _looksLikeArsc(bytes)) {
            localeArscs.add(bytes);
          }
        }

        if ((baseArsc != null && _looksLikeArsc(baseArsc)) ||
            localeArscs.isNotEmpty) {
          label = ApkLabelParser.readApplicationLabel(
            manifest,
            resourcesArsc: baseArsc,
            extraResources: localeArscs,
          );
        }
      }

      if (label == null || label.isEmpty) return null;
      _labelCache[cacheKey] = label;
      if (label == app.name) return null;
      return app.copyWith(name: label, apkPath: baseApk);
    } catch (_) {
      // Do not cache failures — retry on next refresh.
      return null;
    }
  }

  List<String> _allApkPaths(String pmPathOutput) {
    return RegExp(r'package:(.+)')
        .allMatches(pmPathOutput)
        .map((m) => m.group(1)!.trim())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  String? _pickBaseApkPath(String pmPathOutput) {
    final paths = _allApkPaths(pmPathOutput);
    if (paths.isEmpty) return null;
    return paths.firstWhere(
      (p) => p.endsWith('base.apk') || (!p.contains('split_') && p.endsWith('.apk')),
      orElse: () => paths.first,
    );
  }

  Future<Uint8List?> _readApkEntry(
    String serial,
    String apkPath,
    String entry, {
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    final viaExec = await _execOutBytes(
      serial,
      ['unzip', '-p', apkPath, entry],
      maxBytes: maxBytes,
    );
    if (viaExec != null && viaExec.isNotEmpty) return viaExec;
    return _pullEntryViaTmp(serial, apkPath, entry, maxBytes: maxBytes);
  }

  Future<Uint8List?> _pullEntryViaTmp(
    String serial,
    String apkPath,
    String entry, {
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    final tag = '${DateTime.now().microsecondsSinceEpoch}_$entry'
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final remote = '/data/local/tmp/_adb_utils_$tag.bin';
    final local = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}adb_utils_$tag.bin',
    );
    try {
      await _shell(
        serial,
        'unzip -p ${shellQuote(apkPath)} ${shellQuote(entry)} > $remote',
        timeout: const Duration(seconds: 30),
      );
      final pull = await _run(
        ['pull', remote, local.path],
        serial: serial,
        timeout: const Duration(seconds: 40),
      );
      await _shell(serial, 'rm -f $remote', timeout: const Duration(seconds: 5));
      if (pull.exitCode != 0 || !local.existsSync()) return null;
      final bytes = Uint8List.fromList(local.readAsBytesSync());
      try {
        local.deleteSync();
      } catch (_) {}
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return bytes;
    } catch (_) {
      try {
        await _shell(serial, 'rm -f $remote', timeout: const Duration(seconds: 5));
      } catch (_) {}
      try {
        if (local.existsSync()) local.deleteSync();
      } catch (_) {}
      return null;
    }
  }

  Future<Uint8List?> _execOutBytes(
    String serial,
    List<String> remoteArgs, {
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    try {
      final process = await Process.start(
        adbPath,
        ['-s', serial, 'exec-out', ...remoteArgs],
        runInShell: false,
      );
      // Critical on Windows: unread stderr can fill the pipe and deadlock adb.
      final stderrDone = process.stderr.drain<void>();
      final chunks = <int>[];
      var overflow = false;
      await for (final chunk in process.stdout) {
        chunks.addAll(chunk);
        if (chunks.length > maxBytes) {
          overflow = true;
          process.kill();
          break;
        }
      }
      await stderrDone.timeout(const Duration(seconds: 5), onTimeout: () {});
      final code = await process.exitCode.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      if (overflow || code != 0 || chunks.isEmpty) return null;
      if (chunks.length < 256) {
        final text = utf8.decode(chunks, allowMalformed: true).toLowerCase();
        if (text.contains('unzip:') ||
            text.contains('not found') ||
            text.contains('error:') ||
            text.contains('no such')) {
          return null;
        }
      }
      return Uint8List.fromList(chunks);
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeAxml(Uint8List data) =>
      data.length >= 4 && data[0] == 0x03 && data[1] == 0x00;

  bool _looksLikeArsc(Uint8List data) =>
      data.length >= 4 && data[0] == 0x02 && data[1] == 0x00;

  String _guessLabel(String packageName) {
    final parts = packageName.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return packageName;
    final last = parts.last;
    if (last.length <= 2 && parts.length >= 2) {
      return _titleCase(parts[parts.length - 2]);
    }
    return _titleCase(last);
  }

  final Map<String, String> _labelCache = {};

  Future<String?> installApk(String serial, String apkPath) async {
    final file = File(apkPath);
    if (!file.existsSync()) return '找不到 APK 文件：$apkPath';
    try {
      final result = await _run(
        ['install', '-r', apkPath],
        serial: serial,
        timeout: const Duration(minutes: 3),
      );
      if (result.exitCode == 0) return null;
      final msg = '${result.stdout}\n${result.stderr}'.trim();
      return msg.isEmpty ? '安装失败' : msg;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> uninstallApp(String serial, String packageName) async {
    try {
      final result = await _run(['uninstall', packageName], serial: serial);
      if (result.exitCode == 0) return null;
      final msg = '${result.stdout}\n${result.stderr}'.trim();
      return msg.isEmpty ? '卸载失败' : msg;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> launchApp(String serial, String packageName) async {
    try {
      final out = await _shell(
        serial,
        'monkey -p $packageName -c android.intent.category.LAUNCHER 1',
      );
      if (out.toLowerCase().contains('error') || out.toLowerCase().contains('no activities')) {
        return out.trim();
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<FileEntry>> listFiles(
    String serial,
    String path, {
    String? runAsPackage,
  }) async {
    final normalized = _normalizeRemotePath(path);
    final pkg = runAsPackage ??
        _packageFromDataPath(normalized) ??
        _packageFromAndroidDataPath(normalized);

    // App private: /data/data/<pkg>/...
    if (pkg != null && normalized.startsWith('/data/data/$pkg')) {
      return _listPrivateAppDir(serial, normalized, pkg);
    }

    // External app-bound: /sdcard|storage/.../Android/data[/pkg[/...]]
    if (_isUnderAndroidData(normalized)) {
      return _listAndroidDataPath(serial, normalized, packageHint: pkg);
    }

    return _listWithPathFallback(serial, normalized);
  }

  Future<List<FileEntry>> _listPrivateAppDir(
    String serial,
    String normalized,
    String pkg,
  ) async {
    final rel = normalized == '/data/data/$pkg'
        ? '.'
        : normalized.substring('/data/data/$pkg/'.length);
    String stdout = '';
    try {
      stdout = await _shell(
        serial,
        'run-as ${shellQuote(pkg)} ls -la ${shellQuote(rel)}',
        timeout: const Duration(seconds: 10),
      );
      final lower = stdout.toLowerCase();
      if (lower.contains('not debuggable') ||
          lower.contains('permission denied') ||
          lower.contains('run-as:') ||
          lower.contains('no such file')) {
        stdout = '';
      }
    } catch (_) {
      stdout = '';
    }

    if (stdout.trim().isEmpty) {
      try {
        return await _listAndroidDataPath(
          serial,
          '/sdcard/Android/data/$pkg${rel == '.' ? '' : '/$rel'}',
          packageHint: pkg,
        );
      } catch (_) {}
      try {
        stdout = await _shell(
          serial,
          'su -c "ls -la ${shellQuote(normalized)}"',
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        stdout = '';
      }
    }

    if (stdout.trim().isEmpty) {
      throw AdbException(
        '无法打开应用私有目录（需可调试应用或 root）。可改试 /sdcard/Android/data/$pkg',
      );
    }
    return _parseLsOutput(stdout, normalized);
  }

  Future<List<FileEntry>> _listAndroidDataPath(
    String serial,
    String normalized, {
    String? packageHint,
  }) async {
    // Parent Android/data: may be empty/denied on Android 11+ → synthesize from packages.
    if (_isAndroidDataRoot(normalized)) {
      try {
        final listed = await _listWithPathFallback(serial, normalized);
        final real = listed
            .where((e) => e.name != '.nomedia' && !e.name.startsWith('.'))
            .toList();
        if (real.isNotEmpty) return listed;
      } catch (_) {}
      return _synthesizeAndroidDataPackages(serial, normalized);
    }

    try {
      return await _listWithPathFallback(serial, normalized);
    } catch (e) {
      final pkg = packageHint ?? _packageFromAndroidDataPath(normalized);
      if (pkg != null) {
        final parent = normalized.contains('/')
            ? normalized.substring(0, normalized.lastIndexOf('/'))
            : normalized;
        if (_isUnderAndroidData(parent) && !_isAndroidDataRoot(parent)) {
          try {
            final siblings = await _listWithPathFallback(serial, parent);
            final missing = normalized.split('/').last;
            throw AdbException(
              '找不到「$missing」。\n当前目录可见：'
              '${siblings.map((s) => s.name).take(12).join('、')}'
              '${siblings.length > 12 ? '…' : ''}',
            );
          } catch (inner) {
            if (inner is AdbException && inner.message.contains('找不到')) {
              rethrow;
            }
          }
        }
      }
      rethrow;
    }
  }

  Future<List<FileEntry>> _synthesizeAndroidDataPackages(
    String serial,
    String root,
  ) async {
    final displayRoot = _normalizeRemotePath(root);
    final out = await _shell(
      serial,
      r'pm list packages | cut -d: -f2 | while read p; do '
      r'[ -d /sdcard/Android/data/$p ] && echo $p; '
      r'done',
      timeout: const Duration(seconds: 60),
    );
    final entries = <FileEntry>[];
    for (final line in const LineSplitter().convert(out)) {
      final name = line.trim();
      if (name.isEmpty) continue;
      entries.add(
        FileEntry(
          name: name,
          kind: FileKind.folder,
          sizeLabel: '--',
          modified: '—',
          path: displayRoot.endsWith('/')
              ? '$displayRoot$name'
              : '$displayRoot/$name',
        ),
      );
    }
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (entries.isEmpty) {
      throw AdbException('无法列出 Android/data（可能被系统限制）');
    }
    return entries;
  }

  Future<List<FileEntry>> _listWithPathFallback(
    String serial,
    String normalized,
  ) async {
    Object? lastError;
    for (final candidate in _pathCandidates(normalized)) {
      try {
        final out = await _shell(
          serial,
          'ls -la ${shellQuote(candidate)}',
          timeout: const Duration(seconds: 20),
        );
        final lower = out.toLowerCase();
        if (lower.contains('permission denied') ||
            lower.contains('no such file') ||
            lower.contains('not a directory')) {
          lastError = AdbException(out.trim());
          continue;
        }
        return _parseLsOutput(out, normalized);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? AdbException('无法列出目录：$normalized');
  }

  String _normalizeRemotePath(String path) {
    if (path.isEmpty) return '/storage/emulated/0';
    var p = path.replaceAll('\\', '/').trim();
    if (!p.startsWith('/')) p = '/$p';
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }

    // /sdcard is a symlink to external storage on most devices. Canonicalize so
    // we never end up with /storage/emulated/0/sdcard by mistake.
    if (p == '/sdcard' || p.startsWith('/sdcard/')) {
      p = '/storage/emulated/0${p.substring('/sdcard'.length)}';
    }
    if (p == '/storage/self/primary' || p.startsWith('/storage/self/primary/')) {
      p = '/storage/emulated/0${p.substring('/storage/self/primary'.length)}';
    }
    // Collapse mistaken nested alias: .../0/sdcard(/...)
    const nested = '/storage/emulated/0/sdcard';
    while (p == nested || p.startsWith('$nested/')) {
      p = '/storage/emulated/0${p.substring(nested.length)}';
      if (p.isEmpty) p = '/storage/emulated/0';
    }
    return p;
  }

  List<String> _pathCandidates(String path) {
    final normalized = _normalizeRemotePath(path);
    final results = <String>[normalized];
    // Also try the legacy /sdcard alias for older firmwares.
    if (normalized == '/storage/emulated/0' ||
        normalized.startsWith('/storage/emulated/0/')) {
      final alias =
          '/sdcard${normalized.substring('/storage/emulated/0'.length)}';
      if (alias != normalized) results.add(alias);
    }
    return results;
  }

  bool _isUnderAndroidData(String path) {
    final p = _normalizeRemotePath(path);
    return p == '/storage/emulated/0/Android/data' ||
        p.startsWith('/storage/emulated/0/Android/data/');
  }

  bool _isAndroidDataRoot(String path) {
    return _normalizeRemotePath(path) == '/storage/emulated/0/Android/data';
  }

  String? _packageFromAndroidDataPath(String path) {
    final p = _normalizeRemotePath(path);
    const marker = '/Android/data/';
    final i = p.indexOf(marker);
    if (i < 0) return null;
    final rest = p.substring(i + marker.length);
    if (rest.isEmpty) return null;
    final pkg = rest.split('/').first;
    if (pkg.contains('.')) return pkg;
    return null;
  }

  String? _packageFromDataPath(String path) {
    final parts = path.split('/');
    if (parts.length >= 4 && parts[1] == 'data' && parts[2] == 'data') {
      final pkg = parts[3];
      if (pkg.contains('.')) return pkg;
    }
    return null;
  }

  List<FileEntry> _parseLsOutput(String stdout, String normalized) {
    final entries = <FileEntry>[];
    for (final line in const LineSplitter().convert(stdout)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('total')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 6) continue;

      final perm = parts[0];
      if (!RegExp(r'^[-dlcbps]').hasMatch(perm)) continue;

      final isDir = perm.startsWith('d');
      // Symlinks (l…) are not navigated as folders — avoids /sdcard loops.
      if (perm.startsWith('l')) continue;

      String name;
      String modified;
      int sizeBytes = 0;

      if (parts.length >= 8 && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(parts[5])) {
        sizeBytes = int.tryParse(parts[4]) ?? 0;
        modified = '${parts[5]} ${parts[6]}';
        name = parts.sublist(7).join(' ');
      } else if (parts.length >= 8) {
        sizeBytes = int.tryParse(parts[4]) ?? 0;
        modified = '${parts[5]} ${parts[6]}';
        name = parts.sublist(7).join(' ');
      } else {
        name = parts.last;
        modified = '—';
      }

      if (name == '.' || name == '..') continue;
      if (name.contains(' -> ')) {
        name = name.split(' -> ').first.trim();
      }
      // Ignore absolute junk names from odd ls output.
      if (name.startsWith('/')) continue;
      if (name == 'sdcard' &&
          (normalized == '/storage/emulated/0' || normalized == '/sdcard')) {
        // Nested "sdcard" under external storage is almost always a bogus link.
        continue;
      }

      entries.add(
        FileEntry(
          name: name,
          kind: isDir ? FileKind.folder : _guessKind(name),
          sizeLabel: isDir ? '--' : _formatBytes(sizeBytes),
          modified: modified,
          path: normalized.endsWith('/') ? '$normalized$name' : '$normalized/$name',
          sizeBytes: isDir ? 0 : sizeBytes,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  Future<void> createFolder(String serial, String path) async {
    await _shell(serial, 'mkdir -p ${shellQuote(path)}');
  }

  Future<void> deletePaths(String serial, List<String> paths) async {
    if (paths.isEmpty) return;
    final joined = paths.map(shellQuote).join(' ');
    await _shell(serial, 'rm -rf $joined');
  }

  Future<String?> pushFile(String serial, String localPath, String remoteDir) async {
    final file = File(localPath);
    if (!file.existsSync()) return '找不到本地文件：$localPath';
    final name = localPath.replaceAll('\\', '/').split('/').last;
    final remote = remoteDir.endsWith('/') ? '$remoteDir$name' : '$remoteDir/$name';
    try {
      final result = await _run(
        ['push', localPath, remote],
        serial: serial,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) return null;
      return '${result.stdout}\n${result.stderr}'.trim();
    } catch (e) {
      return e.toString();
    }
  }

  static const int previewTextMaxBytes = 512 * 1024;
  static const int previewJsonMaxBytes = 1024 * 1024;
  static const int previewLogMaxBytes = 2 * 1024 * 1024;
  static const int previewImageMaxBytes = 8 * 1024 * 1024;

  int _previewMaxBytes(FileKind kind) {
    return switch (kind) {
      FileKind.image => previewImageMaxBytes,
      FileKind.log => previewLogMaxBytes,
      FileKind.json => previewJsonMaxBytes,
      _ => previewTextMaxBytes,
    };
  }

  /// Reads remote file bytes for in-app preview (text/log/image).
  Future<FilePreviewData> readFilePreview(
    String serial,
    FileEntry entry, {
    String? runAsPackage,
  }) async {
    final path = _normalizeRemotePath(entry.path);
    final pkg = runAsPackage ??
        _packageFromDataPath(path) ??
        _packageFromAndroidDataPath(path);

    final maxBytes = _previewMaxBytes(entry.kind);

    if (!entry.isDirectory &&
        entry.sizeBytes > 0 &&
        entry.kind != FileKind.log &&
        entry.sizeBytes > maxBytes) {
      return FilePreviewData.tooLarge(
        entry.kind,
        maxBytes: maxBytes,
        actualBytes: entry.sizeBytes,
      );
    }

    if (!entry.isPreviewable) {
      return const FilePreviewData.unsupported();
    }

    final useTail = entry.kind == FileKind.log &&
        entry.sizeBytes > maxBytes;

    Uint8List? bytes;
    if (pkg != null && path.startsWith('/data/data/$pkg')) {
      final rel = path == '/data/data/$pkg'
          ? entry.name
          : path.substring('/data/data/$pkg/'.length);
      bytes = await _readPrivateFileBytes(
        serial,
        pkg,
        rel,
        maxBytes: maxBytes,
        tail: useTail,
      );
    } else {
      bytes = await _readPublicFileBytes(
        serial,
        path,
        maxBytes: maxBytes,
        tail: useTail,
      );
    }

    if (bytes == null || bytes.isEmpty) {
      return const FilePreviewData.error('无法读取文件（权限不足或路径无效）');
    }

    final truncated = entry.kind == FileKind.log
        ? (entry.sizeBytes > bytes.length || bytes.length >= maxBytes)
        : (entry.sizeBytes > 0
            ? entry.sizeBytes > bytes.length
            : bytes.length >= maxBytes);

    if (entry.kind == FileKind.image) {
      return FilePreviewData.image(bytes, truncated: truncated);
    }

    if (entry.kind != FileKind.log && entry.kind != FileKind.json && _looksBinary(bytes)) {
      return const FilePreviewData.error('文件似乎是二进制内容，请下载后查看');
    }

    var text = utf8.decode(bytes, allowMalformed: true);
    if (entry.kind == FileKind.json) {
      text = _formatJsonPreview(text);
    }
    return FilePreviewData.text(
      text,
      truncated: truncated,
      fromTail: useTail,
    );
  }

  String _formatJsonPreview(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    try {
      final decoded = jsonDecode(trimmed);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  Future<Uint8List?> _readPublicFileBytes(
    String serial,
    String path, {
    required int maxBytes,
    required bool tail,
  }) async {
    if (tail) {
      final tailed = await _execOutBytes(
        serial,
        ['tail', '-c', '$maxBytes', path],
        maxBytes: maxBytes + 4096,
      );
      if (tailed != null && tailed.isNotEmpty) return tailed;
    }

    final bytes = await _execOutBytes(serial, ['cat', path], maxBytes: maxBytes);
    if (bytes != null && bytes.isNotEmpty) return bytes;

    return _pullRemoteFileBytes(
      serial,
      path,
      maxBytes: maxBytes,
      tail: tail,
    );
  }

  Future<Uint8List?> _readPrivateFileBytes(
    String serial,
    String pkg,
    String relPath, {
    required int maxBytes,
    required bool tail,
  }) async {
    if (tail) {
      final tailed = await _execOutBytes(
        serial,
        ['run-as', pkg, 'tail', '-c', '$maxBytes', relPath],
        maxBytes: maxBytes + 4096,
      );
      if (tailed != null && tailed.isNotEmpty) return tailed;

      final cmd =
          'run-as ${shellQuote(pkg)} tail -c $maxBytes ${shellQuote(relPath)}';
      final viaSh = await _execOutBytes(
        serial,
        ['sh', '-c', cmd],
        maxBytes: maxBytes + 4096,
      );
      if (viaSh != null && viaSh.isNotEmpty) return viaSh;
    }

    final direct = await _execOutBytes(
      serial,
      ['run-as', pkg, 'cat', relPath],
      maxBytes: maxBytes,
    );
    if (direct != null && direct.isNotEmpty) return direct;

    final cmd = 'run-as ${shellQuote(pkg)} cat ${shellQuote(relPath)}';
    return _execOutBytes(
      serial,
      ['sh', '-c', cmd],
      maxBytes: maxBytes,
    );
  }

  Future<Uint8List?> _pullRemoteFileBytes(
    String serial,
    String remotePath, {
    required int maxBytes,
    bool tail = false,
  }) async {
    final tag = '${DateTime.now().microsecondsSinceEpoch}_pull';
    final local = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}adb_utils_$tag.bin',
    );
    try {
      final pull = await _run(
        ['pull', remotePath, local.path],
        serial: serial,
        timeout: const Duration(minutes: 2),
      );
      if (pull.exitCode != 0 || !local.existsSync()) return null;
      var bytes = local.readAsBytesSync();
      if (bytes.isEmpty) return null;
      if (tail && bytes.length > maxBytes) {
        bytes = bytes.sublist(bytes.length - maxBytes);
      } else if (bytes.length > maxBytes) {
        return null;
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    } finally {
      try {
        if (local.existsSync()) local.deleteSync();
      } catch (_) {}
    }
  }

  bool _looksBinary(Uint8List bytes) {
    final sample = bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes;
    var nonText = 0;
    for (final b in sample) {
      if (b == 0) return true;
      if (b < 9 || (b > 13 && b < 32)) nonText++;
    }
    return nonText > sample.length * 0.1;
  }

  Future<String?> pullFile(String serial, String remotePath, String localPath) async {
    try {
      final result = await _run(
        ['pull', remotePath, localPath],
        serial: serial,
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode == 0) return null;
      return '${result.stdout}\n${result.stderr}'.trim();
    } catch (e) {
      return e.toString();
    }
  }

  Future<String> adbVersion() async {
    try {
      final result = await _run(['version']);
      final text = result.stdout.toString().trim();
      if (text.isEmpty) return result.stderr.toString().trim();
      return text.split('\n').first.trim();
    } catch (e) {
      return '无法读取：$e';
    }
  }

  Future<String?> captureScreenshot(String serial, String localPath) async {
    final bytes = await _execOutBytes(
      serial,
      ['screencap', '-p'],
      maxBytes: 32 * 1024 * 1024,
    );
    if (bytes == null || bytes.isEmpty) return '截图失败（设备可能不支持 screencap）';
    try {
      File(localPath).parent.createSync(recursive: true);
      await File(localPath).writeAsBytes(bytes, flush: true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<StorageMetrics> storageMetrics(String serial) async {
    try {
      final out = await _shell(serial, 'df /data');
      final lines = const LineSplitter().convert(out).where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) return StorageMetrics.empty;
      final parts = lines.last.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) return StorageMetrics.empty;

      // df output units are usually 1K-blocks.
      final totalKb = double.tryParse(parts[1]) ?? 0;
      final usedKb = double.tryParse(parts[2]) ?? 0;
      return StorageMetrics(
        usedGb: usedKb / (1024 * 1024),
        totalGb: totalKb / (1024 * 1024),
      );
    } catch (_) {
      return StorageMetrics.empty;
    }
  }

  Future<MemoryMetrics> memoryMetrics(String serial) async {
    try {
      final text = await _shell(serial, 'cat /proc/meminfo');
      final total = _memKb(text, 'MemTotal');
      final available = _memKb(text, 'MemAvailable') ?? _memKb(text, 'MemFree');
      if (total == null || available == null) return MemoryMetrics.empty;
      final used = (total - available).clamp(0, total);
      // Approximate split: Cached/Buffers as apps-ish remainder vs kernel.
      final cached = _memKb(text, 'Cached') ?? 0;
      final buffers = _memKb(text, 'Buffers') ?? 0;
      final apps = (cached + buffers).clamp(0, used);
      final system = (used - apps).clamp(0, used);
      return MemoryMetrics(
        systemGb: system / (1024 * 1024),
        appsGb: apps / (1024 * 1024),
        totalGb: total / (1024 * 1024),
      );
    } catch (_) {
      return MemoryMetrics.empty;
    }
  }

  Future<DeviceFlags> readDeviceFlags(String serial) async {
    try {
      final out = await _shell(
        serial,
        'settings get global stay_on_while_plugged_in; getprop debug.layout; settings get global adb_wifi_enabled',
      );
      final lines = const LineSplitter().convert(out.trim());
      final stay = lines.isNotEmpty ? (int.tryParse(lines[0].trim()) ?? 0) > 0 : false;
      final layout = lines.length > 1 && lines[1].trim().toLowerCase() == 'true';
      final wifi = lines.length > 2 && (lines[2].trim() == '1' || lines[2].trim().toLowerCase() == 'true');
      return DeviceFlags(
        stayAwake: stay,
        showLayoutBounds: layout,
        wirelessDebugging: wifi,
      );
    } catch (_) {
      return const DeviceFlags();
    }
  }

  Future<String> runCommand(String? serial, String command) async {
    final parts = _splitCommand(command.trim());
    if (parts.isEmpty) return '';
    try {
      final result = await _run(parts, serial: serial, timeout: const Duration(minutes: 2));
      final out = result.stdout.toString();
      final err = result.stderr.toString();
      if (out.isNotEmpty && err.isNotEmpty) return '$out\n$err';
      if (out.isNotEmpty) return out;
      if (err.isNotEmpty) return err;
      return '(exit ${result.exitCode})';
    } catch (e) {
      return '错误：$e';
    }
  }

  Stream<LogEntry> startLogcat(String serial) {
    final controller = StreamController<LogEntry>();
    () async {
      try {
        await stopLogcat();
        // Warm process map so package filters work ASAP.
        unawaited(_refreshPidPackageMap(serial));
        _pidMapTimer?.cancel();
        _pidMapTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          unawaited(_refreshPidPackageMap(serial));
        });

        _logcatProcess = await Process.start(
          adbPath,
          ['-s', serial, 'logcat', '-v', 'threadtime'],
        );
        _logcatProcess!.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            final entry = _parseLogLine(line);
            if (entry == null || controller.isClosed) return;
            final pkg = _pidToPackage[entry.pid];
            controller.add(pkg == null ? entry : entry.copyWith(packageName: pkg));
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
          onDone: () {
            _pidMapTimer?.cancel();
            _pidMapTimer = null;
            if (!controller.isClosed) controller.close();
          },
        );
        _logcatProcess!.stderr.transform(utf8.decoder).listen((_) {});
      } catch (e, st) {
        _pidMapTimer?.cancel();
        _pidMapTimer = null;
        if (!controller.isClosed) {
          controller.addError(e, st);
          await controller.close();
        }
      }
    }();
    return controller.stream;
  }

  Future<void> stopLogcat() async {
    _pidMapTimer?.cancel();
    _pidMapTimer = null;
    _logcatProcess?.kill();
    _logcatProcess = null;
  }

  /// pid -> package/process name, refreshed while logcat is running.
  final Map<String, String> _pidToPackage = {};
  Timer? _pidMapTimer;

  String? packageForPid(String pid) => _pidToPackage[pid];

  Future<void> _refreshPidPackageMap(String serial) async {
    try {
      final out = await _shell(
        serial,
        // Prefer toybox columns; fall back to classic ps.
        'ps -A -o PID,NAME 2>/dev/null || ps -A',
        timeout: const Duration(seconds: 8),
      );
      final map = <String, String>{};
      for (final raw in const LineSplitter().convert(out)) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        final upper = line.toUpperCase();
        if (upper.startsWith('PID') || upper.startsWith('USER')) continue;

        final cols = line.split(RegExp(r'\s+'));
        if (cols.length < 2) continue;

        if (RegExp(r'^\d+$').hasMatch(cols[0])) {
          // PID NAME
          map[cols[0]] = cols.last;
          continue;
        }

        // classic: USER PID PPID ... NAME
        final pidIdx = cols.indexWhere((c) => RegExp(r'^\d+$').hasMatch(c));
        if (pidIdx >= 0 && pidIdx < cols.length - 1) {
          map[cols[pidIdx]] = cols.last;
        }
      }
      if (map.isNotEmpty) {
        _pidToPackage
          ..clear()
          ..addAll(map);
      }
    } catch (_) {
      // Keep previous map on failure.
    }
  }

  Future<bool> setStayAwake(String serial, bool enabled) async {
    try {
      await _shell(
        serial,
        'settings put global stay_on_while_plugged_in ${enabled ? '3' : '0'}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setShowLayoutBounds(String serial, bool enabled) async {
    try {
      await _shell(serial, 'setprop debug.layout ${enabled ? 'true' : 'false'}');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setWirelessDebugging(String serial, bool enabled) async {
    try {
      await _shell(serial, 'settings put global adb_wifi_enabled ${enabled ? '1' : '0'}');
      return true;
    } catch (_) {
      return false;
    }
  }

  LogEntry? _parseLogLine(String line) {
    final re = RegExp(
      r'^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+)\s+(\d+)\s+(\d+)\s+([VDIWEF])\s+([^:]+):\s?(.*)$',
    );
    final m = re.firstMatch(line);
    if (m == null) return null;
    return LogEntry(
      timestamp: m.group(1)!,
      pid: m.group(2)!,
      tid: m.group(3)!,
      level: _levelFromCode(m.group(4)!),
      tag: m.group(5)!.trim(),
      message: m.group(6) ?? '',
    );
  }

  LogLevel _levelFromCode(String code) {
    switch (code) {
      case 'V':
        return LogLevel.verbose;
      case 'D':
        return LogLevel.debug;
      case 'I':
        return LogLevel.info;
      case 'W':
        return LogLevel.warning;
      case 'E':
      case 'F':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }

  int? _memKb(String text, String key) {
    final m = RegExp('$key:\\s*(\\d+)').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  FileKind _guessKind(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) return FileKind.apk;
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      return FileKind.image;
    }
    if (lower.endsWith('.log') ||
        lower.endsWith('.logcat') ||
        lower.endsWith('.trace') ||
        lower.endsWith('.tombstone') ||
        lower.endsWith('.crash') ||
        lower.endsWith('.out') ||
        lower.contains('logcat') ||
        lower.startsWith('log_') ||
        lower.endsWith('_log')) {
      return FileKind.log;
    }
    if (lower.endsWith('.json') ||
        lower.endsWith('.geojson') ||
        lower.endsWith('.jsonc')) {
      return FileKind.json;
    }
    if (lower.endsWith('.txt') ||
        lower.endsWith('.xml') ||
        lower.endsWith('.csv') ||
        lower.endsWith('.md') ||
        lower.endsWith('.yaml') ||
        lower.endsWith('.yml') ||
        lower.endsWith('.properties') ||
        lower.endsWith('.conf') ||
        lower.endsWith('.cfg') ||
        lower.endsWith('.ini') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.css') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.sh') ||
        lower.endsWith('.gradle') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.java') ||
        lower.endsWith('.dart') ||
        lower.endsWith('.pro') ||
        lower.endsWith('.gitignore') ||
        lower.endsWith('.env')) {
      return FileKind.text;
    }
    return FileKind.other;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String shellQuote(String value) {
    if (!value.contains(RegExp(r'''[\s'"\\$`]'''))) return value;
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  List<String> _splitCommand(String command) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (c == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (c == ' ' && !inQuotes) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(c);
    }
    if (buffer.isNotEmpty) result.add(buffer.toString());
    return result;
  }
}

enum FilePreviewKind { text, image, unsupported, tooLarge, error }

class FilePreviewData {
  const FilePreviewData._({
    required this.kind,
    this.text,
    this.bytes,
    this.truncated = false,
    this.fromTail = false,
    this.error,
    this.maxBytes,
    this.actualBytes,
  });

  const FilePreviewData.text(
    String content, {
    bool truncated = false,
    bool fromTail = false,
  }) : this._(
          kind: FilePreviewKind.text,
          text: content,
          truncated: truncated,
          fromTail: fromTail,
        );

  const FilePreviewData.image(Uint8List data, {bool truncated = false})
      : this._(
          kind: FilePreviewKind.image,
          bytes: data,
          truncated: truncated,
        );

  const FilePreviewData.unsupported()
      : this._(kind: FilePreviewKind.unsupported);

  const FilePreviewData.error(String message)
      : this._(kind: FilePreviewKind.error, error: message);

  FilePreviewData.tooLarge(
    FileKind fileKind, {
    required int maxBytes,
    required int actualBytes,
  }) : this._(
          kind: FilePreviewKind.tooLarge,
          maxBytes: maxBytes,
          actualBytes: actualBytes,
          error: fileKind == FileKind.image
              ? '图片过大'
              : fileKind == FileKind.log
                  ? '日志过大'
                  : fileKind == FileKind.json
                      ? 'JSON 过大'
                      : '文件过大',
        );

  final FilePreviewKind kind;
  final String? text;
  final Uint8List? bytes;
  final bool truncated;
  final bool fromTail;
  final String? error;
  final int? maxBytes;
  final int? actualBytes;
}

class DeviceFlags {
  const DeviceFlags({
    this.stayAwake = false,
    this.showLayoutBounds = false,
    this.wirelessDebugging = false,
  });

  final bool stayAwake;
  final bool showLayoutBounds;
  final bool wirelessDebugging;
}
