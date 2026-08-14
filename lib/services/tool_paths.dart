import 'dart:io';

/// Resolves bundled Android platform-tools next to the app executable.
abstract final class ToolPaths {
  static String? _adb;
  static String? _sqlite3;
  static String? _platformToolsDir;

  static String get platformToolsDir {
    final cached = _platformToolsDir;
    if (cached != null) return cached;

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = <String>[
      '$exeDir${Platform.pathSeparator}platform-tools',
      // flutter run sometimes keeps extras one level up from the runner exe
      // depending on install layout; also support project-relative for tests.
      '${Directory.current.path}${Platform.pathSeparator}windows'
          '${Platform.pathSeparator}platform-tools',
    ];

    for (final dir in candidates) {
      final adbName = Platform.isWindows ? 'adb.exe' : 'adb';
      if (File('$dir${Platform.pathSeparator}$adbName').existsSync()) {
        _platformToolsDir = dir;
        return dir;
      }
    }

    _platformToolsDir = candidates.first;
    return _platformToolsDir!;
  }

  static String resolveAdb() {
    final cached = _adb;
    if (cached != null) return cached;

    final adbName = Platform.isWindows ? 'adb.exe' : 'adb';
    final bundled = File(
      '$platformToolsDir${Platform.pathSeparator}$adbName',
    );
    if (bundled.existsSync()) {
      _adb = bundled.path;
      return _adb!;
    }

    // Fallback: PATH / SDK
    for (final env in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final root = Platform.environment[env];
      if (root == null || root.isEmpty) continue;
      final sdkAdb = File(
        '$root${Platform.pathSeparator}platform-tools'
        '${Platform.pathSeparator}$adbName',
      );
      if (sdkAdb.existsSync()) {
        _adb = sdkAdb.path;
        return _adb!;
      }
    }

    _adb = Platform.isWindows ? 'adb.exe' : 'adb';
    return _adb!;
  }

  static String resolveSqlite3() {
    final cached = _sqlite3;
    if (cached != null) return cached;

    final name = Platform.isWindows ? 'sqlite3.exe' : 'sqlite3';
    final nextToAdb = File(
      '${File(resolveAdb()).parent.path}${Platform.pathSeparator}$name',
    );
    if (nextToAdb.existsSync()) {
      _sqlite3 = nextToAdb.path;
      return _sqlite3!;
    }

    final bundled = File(
      '$platformToolsDir${Platform.pathSeparator}$name',
    );
    if (bundled.existsSync()) {
      _sqlite3 = bundled.path;
      return _sqlite3!;
    }

    for (final env in ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final root = Platform.environment[env];
      if (root == null || root.isEmpty) continue;
      final sdk = File(
        '$root${Platform.pathSeparator}platform-tools'
        '${Platform.pathSeparator}$name',
      );
      if (sdk.existsSync()) {
        _sqlite3 = sdk.path;
        return _sqlite3!;
      }
    }

    _sqlite3 = name;
    return _sqlite3!;
  }
}
