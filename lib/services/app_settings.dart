import 'dart:convert';
import 'dart:io';

enum AdbPathMode { bundled, system, custom }

enum AppThemePref { system, dark, light }

enum DbRefreshPref { off, timed, realtime }

enum ScreenshotHotkey { f5, ctrlShiftS }

class AppSettings {
  AppSettings({
    this.adbPathMode = AdbPathMode.bundled,
    this.customAdbPath = '',
    this.saveDirectory = '',
    this.autoRefreshOnStartup = true,
    this.rememberLastDevice = true,
    this.lastDeviceId = '',
    this.autoSelectOnConnect = true,
    this.devicePollSeconds = 2,
    this.logcatCycleBufferKb = 1024,
    this.defaultLogLevel,
    this.dbRefreshMode = DbRefreshPref.off,
    this.dbRefreshSeconds = 5,
    this.dbQueryLimit = 50,
    this.themePref = AppThemePref.dark,
    this.checkUpdatesOnStartup = true,
    this.terminalFontSize = 13,
    this.screenshotHotkey = ScreenshotHotkey.f5,
    this.confirmDangerousActions = true,
    List<String>? logcatSearchHistory,
  }) : logcatSearchHistory = List<String>.from(logcatSearchHistory ?? []);

  AdbPathMode adbPathMode;
  String customAdbPath;
  String saveDirectory;
  bool autoRefreshOnStartup;
  bool rememberLastDevice;
  String lastDeviceId;
  bool autoSelectOnConnect;
  int devicePollSeconds;
  int logcatCycleBufferKb;
  String? defaultLogLevel;
  DbRefreshPref dbRefreshMode;
  int dbRefreshSeconds;
  int dbQueryLimit;
  AppThemePref themePref;
  bool checkUpdatesOnStartup;
  double terminalFontSize;
  ScreenshotHotkey screenshotHotkey;
  bool confirmDangerousActions;
  List<String> logcatSearchHistory;

  static const int maxLogcatSearchHistory = 20;

  static String defaultDownloads() {
    final sep = Platform.pathSeparator;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;

    // Prefer the real Windows "Downloads" known folder (may be redirected /
    // localized, e.g. OneDrive\Downloads or 下载).
    final known = _windowsDownloadsKnownFolder();
    final candidates = <String>[
      if (known != null && known.isNotEmpty) known,
      '$home${sep}Downloads',
      '$home$sep${'下载'}',
      '$home${sep}Documents',
      home,
    ];

    String? base;
    for (final c in candidates) {
      try {
        final dir = Directory(c);
        if (dir.existsSync()) {
          base = dir.path;
          break;
        }
      } catch (_) {}
    }
    base ??= '$home${sep}Downloads';

    final target = '$base${sep}adb_utils';
    try {
      Directory(target).createSync(recursive: true);
    } catch (_) {}
    return target;
  }

  /// Resolves the current user's Downloads folder on Windows via registry.
  static String? _windowsDownloadsKnownFolder() {
    if (!Platform.isWindows) return null;
    try {
      final result = Process.runSync(
        'reg',
        [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders',
          '/v',
          '{374DE290-123F-4565-9164-39C4925E467B}',
        ],
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      final out = '${result.stdout}';
      // REG_EXPAND_SZ    {guid}    C:\Users\...\Downloads
      final match = RegExp(
        r'\{374DE290-123F-4565-9164-39C4925E467B\}\s+REG_\w+\s+(.+)$',
        multiLine: true,
      ).firstMatch(out);
      var path = match?.group(1)?.trim();
      if (path == null || path.isEmpty) return null;
      path = path.replaceAll('"', '');
      // Expand %USERPROFILE% etc.
      path = path.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) {
        return Platform.environment[m.group(1)!] ?? m.group(0)!;
      });
      return path;
    } catch (_) {
      return null;
    }
  }

  String get effectiveSaveDirectory {
    final v = saveDirectory.trim();
    if (v.isEmpty) return defaultDownloads();
    // Normalize slashes on Windows so mixed "C:/Users/..." still works.
    final normalized = Platform.isWindows ? v.replaceAll('/', r'\') : v;
    try {
      Directory(normalized).createSync(recursive: true);
    } catch (_) {}
    return normalized;
  }

  Map<String, dynamic> toJson() => {
        'adbPathMode': adbPathMode.name,
        'customAdbPath': customAdbPath,
        'saveDirectory': saveDirectory,
        'autoRefreshOnStartup': autoRefreshOnStartup,
        'rememberLastDevice': rememberLastDevice,
        'lastDeviceId': lastDeviceId,
        'autoSelectOnConnect': autoSelectOnConnect,
        'devicePollSeconds': devicePollSeconds,
        'devicePollMigratedV2': true,
        'logcatCycleBufferKb': logcatCycleBufferKb,
        'defaultLogLevel': defaultLogLevel,
        'dbRefreshMode': dbRefreshMode.name,
        'dbRefreshSeconds': dbRefreshSeconds,
        'dbQueryLimit': dbQueryLimit,
        'themePref': themePref.name,
        'checkUpdatesOnStartup': checkUpdatesOnStartup,
        'terminalFontSize': terminalFontSize,
        'screenshotHotkey': screenshotHotkey.name,
        'confirmDangerousActions': confirmDangerousActions,
        'logcatSearchHistory': logcatSearchHistory,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    AdbPathMode modeFrom(String? n) => AdbPathMode.values.firstWhere(
          (e) => e.name == n,
          orElse: () => AdbPathMode.bundled,
        );
    return AppSettings(
      adbPathMode: modeFrom(json['adbPathMode'] as String?),
      customAdbPath: json['customAdbPath'] as String? ?? '',
      saveDirectory: json['saveDirectory'] as String? ?? '',
      autoRefreshOnStartup: json['autoRefreshOnStartup'] as bool? ?? true,
      rememberLastDevice: json['rememberLastDevice'] as bool? ?? true,
      lastDeviceId: json['lastDeviceId'] as String? ?? '',
      autoSelectOnConnect: json['autoSelectOnConnect'] as bool? ?? true,
      devicePollSeconds: () {
        final v = json['devicePollSeconds'] as int?;
        // Legacy default was 0 (off). Enable realtime-friendly polling by default.
        if (v == null) return 2;
        if (v == 0 && json['devicePollMigratedV2'] != true) return 2;
        return v;
      }(),
      logcatCycleBufferKb: _logcatCycleBufferKbFromJson(json),
      defaultLogLevel: _validLogLevel(json['defaultLogLevel'] as String?),
      dbRefreshMode: DbRefreshPref.values.firstWhere(
        (e) => e.name == json['dbRefreshMode'],
        orElse: () => DbRefreshPref.off,
      ),
      dbRefreshSeconds: json['dbRefreshSeconds'] as int? ?? 5,
      dbQueryLimit: json['dbQueryLimit'] as int? ?? 50,
      themePref: AppThemePref.values.firstWhere(
        (e) => e.name == json['themePref'],
        orElse: () => AppThemePref.dark,
      ),
      checkUpdatesOnStartup: json['checkUpdatesOnStartup'] as bool? ?? true,
      terminalFontSize: (json['terminalFontSize'] as num?)?.toDouble() ?? 13,
      screenshotHotkey: ScreenshotHotkey.values.firstWhere(
        (e) => e.name == json['screenshotHotkey'],
        orElse: () => ScreenshotHotkey.f5,
      ),
      confirmDangerousActions: json['confirmDangerousActions'] as bool? ?? true,
      logcatSearchHistory: List<String>.from(
        (json['logcatSearchHistory'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty) ??
            const [],
      ),
    );
  }

  void pushLogcatSearchHistory(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final history = List<String>.from(logcatSearchHistory);
    history.removeWhere((e) => e == q);
    history.insert(0, q);
    if (history.length > maxLogcatSearchHistory) {
      history.removeRange(maxLogcatSearchHistory, history.length);
    }
    logcatSearchHistory = history;
  }

  void clearLogcatSearchHistory() {
    logcatSearchHistory = [];
  }

  static int _logcatCycleBufferKbFromJson(Map<String, dynamic> json) {
    final kb = json['logcatCycleBufferKb'] as int?;
    if (kb != null) return kb.clamp(0, 65536);
    // Legacy: logcatBufferSize stored max line count.
    return switch (json['logcatBufferSize'] as int?) {
      1000 => 512,
      8000 => 4096,
      null => 1024,
      _ => 1024,
    };
  }

  static String? _validLogLevel(String? name) {
    const allowed = {'verbose', 'debug', 'info', 'warning', 'error'};
    if (name == null || !allowed.contains(name)) return null;
    return name;
  }
}

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  AppSettings settings = AppSettings();
  File? _file;

  Future<File> _settingsFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final home = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final dir = Directory('$home${Platform.pathSeparator}adb_utils');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _file = File('${dir.path}${Platform.pathSeparator}settings.json');
    return _file!;
  }

  Future<AppSettings> load() async {
    try {
      final file = await _settingsFile();
      if (!file.existsSync()) {
        settings = AppSettings();
        return settings;
      }
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      settings = AppSettings.fromJson(map);
    } catch (_) {
      settings = AppSettings();
    }
    return settings;
  }

  Future<void> save([AppSettings? next]) async {
    if (next != null) settings = next;
    try {
      final file = await _settingsFile();
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (_) {}
  }
}
