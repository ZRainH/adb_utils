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
    this.devicePollSeconds = 0,
    this.logcatBufferSize = 3000,
    this.defaultLogLevel,
    this.dbRefreshMode = DbRefreshPref.off,
    this.dbRefreshSeconds = 5,
    this.dbQueryLimit = 50,
    this.themePref = AppThemePref.dark,
    this.checkUpdatesOnStartup = true,
    this.terminalFontSize = 13,
    this.screenshotHotkey = ScreenshotHotkey.f5,
    this.confirmDangerousActions = true,
  });

  AdbPathMode adbPathMode;
  String customAdbPath;
  String saveDirectory;
  bool autoRefreshOnStartup;
  bool rememberLastDevice;
  String lastDeviceId;
  bool autoSelectOnConnect;
  int devicePollSeconds;
  int logcatBufferSize;
  String? defaultLogLevel;
  DbRefreshPref dbRefreshMode;
  int dbRefreshSeconds;
  int dbQueryLimit;
  AppThemePref themePref;
  bool checkUpdatesOnStartup;
  double terminalFontSize;
  ScreenshotHotkey screenshotHotkey;
  bool confirmDangerousActions;

  static String defaultDownloads() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}adb_utils';
  }

  String get effectiveSaveDirectory {
    final v = saveDirectory.trim();
    return v.isEmpty ? defaultDownloads() : v;
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
        'logcatBufferSize': logcatBufferSize,
        'defaultLogLevel': defaultLogLevel,
        'dbRefreshMode': dbRefreshMode.name,
        'dbRefreshSeconds': dbRefreshSeconds,
        'dbQueryLimit': dbQueryLimit,
        'themePref': themePref.name,
        'checkUpdatesOnStartup': checkUpdatesOnStartup,
        'terminalFontSize': terminalFontSize,
        'screenshotHotkey': screenshotHotkey.name,
        'confirmDangerousActions': confirmDangerousActions,
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
      devicePollSeconds: json['devicePollSeconds'] as int? ?? 0,
      logcatBufferSize: json['logcatBufferSize'] as int? ?? 3000,
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
    );
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
