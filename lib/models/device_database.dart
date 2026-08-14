enum DbAccess {
  /// Readable via adb pull (e.g. /sdcard).
  public,

  /// Readable via `run-as <package>`.
  runAs,

  /// Requires root / su.
  root,
}

class DeviceDatabase {
  const DeviceDatabase({
    required this.name,
    required this.remotePath,
    required this.access,
    this.packageName,
  });

  final String name;
  final String remotePath;
  final DbAccess access;
  final String? packageName;

  String get directory {
    final i = remotePath.lastIndexOf('/');
    if (i <= 0) return remotePath;
    return remotePath.substring(0, i + 1);
  }

  String get relativeUnderPackage {
    if (packageName == null) return name;
    final marker = '/data/data/$packageName/';
    if (remotePath.startsWith(marker)) {
      return remotePath.substring(marker.length);
    }
    return 'databases/$name';
  }
}

class DbQueryResult {
  const DbQueryResult({
    required this.columns,
    required this.rows,
  });

  static const empty = DbQueryResult(columns: [], rows: []);

  final List<String> columns;
  final List<List<String>> rows;
}
