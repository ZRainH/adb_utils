import 'dart:convert';
import 'dart:io';

import '../models/device_database.dart';
import 'adb_service.dart';
import 'tool_paths.dart';

class DeviceDbService {
  DeviceDbService(this.adb);

  final AdbService adb;

  String? _sqlite3Path;
  final Map<String, String> _cache = {};

  Future<String> _sqlite3() async {
    final cached = _sqlite3Path;
    if (cached != null) return cached;

    final path = ToolPaths.resolveSqlite3();
    try {
      final result = await Process.run(path, ['--version']);
      if (result.exitCode == 0) {
        _sqlite3Path = path;
        return path;
      }
    } catch (_) {}

    throw AdbException(
      '未找到 sqlite3。请确认应用目录 platform-tools 中包含 sqlite3'
      '${Platform.isWindows ? '.exe' : ''}。',
    );
  }

  Future<List<DeviceDatabase>> listDatabases(
    String serial, {
    String? packageName,
  }) async {
    if (packageName != null && packageName.isNotEmpty) {
      return listDatabasesForPackage(serial, packageName);
    }

    final byPath = <String, DeviceDatabase>{};

    Future<void> addFind(String root, DbAccess access, {String? packageName}) async {
      try {
        final out = await adb.shell(
          serial,
          'find ${adb.shellQuote(root)} -type f \\( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \\) 2>/dev/null | head -n 200',
          timeout: const Duration(seconds: 45),
        );
        for (final line in const LineSplitter().convert(out)) {
          final path = line.trim();
          if (path.isEmpty || !path.contains('/')) continue;
          final name = path.split('/').last;
          byPath.putIfAbsent(
            path,
            () => DeviceDatabase(
              name: name,
              remotePath: path,
              access: access,
              packageName: packageName,
            ),
          );
        }
      } catch (_) {}
    }

    await addFind('/sdcard', DbAccess.public);
    await addFind('/storage/emulated/0', DbAccess.public);

    // Debuggable / run-as apps (user packages first).
    try {
      final pkgsOut = await adb.shell(serial, 'pm list packages -3');
      final packages = const LineSplitter()
          .convert(pkgsOut)
          .map((l) => l.trim())
          .where((l) => l.startsWith('package:'))
          .map((l) => l.substring(8))
          .take(60)
          .toList();

      const batch = 8;
      for (var i = 0; i < packages.length; i += batch) {
        final slice = packages.skip(i).take(batch).toList();
        final results = await Future.wait(
          slice.map((pkg) => listDatabasesForPackage(serial, pkg)),
        );
        for (final list in results) {
          for (final db in list) {
            byPath.putIfAbsent(db.remotePath, () => db);
          }
        }
      }
    } catch (_) {}

    // Root scan (optional).
    try {
      final out = await adb.shell(
        serial,
        'su -c "find /data/data -type f \\( -name \'*.db\' -o -name \'*.sqlite\' \\) 2>/dev/null | head -n 120"',
        timeout: const Duration(seconds: 30),
      );
      for (final line in const LineSplitter().convert(out)) {
        final path = line.trim();
        if (path.isEmpty || !path.startsWith('/data/data/')) continue;
        final parts = path.split('/');
        final pkg = parts.length > 3 ? parts[3] : null;
        final name = parts.last;
        byPath.putIfAbsent(
          path,
          () => DeviceDatabase(
            name: name,
            remotePath: path,
            access: DbAccess.root,
            packageName: pkg,
          ),
        );
      }
    } catch (_) {}

    final list = byPath.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Fast path: databases for a single package (run-as, then root).
  Future<List<DeviceDatabase>> listDatabasesForPackage(
    String serial,
    String packageName,
  ) async {
    final byPath = <String, DeviceDatabase>{};
    final pkg = packageName.trim();
    if (pkg.isEmpty) return const [];

    try {
      final out = await adb.shell(
        serial,
        'run-as ${adb.shellQuote(pkg)} sh -c "ls databases 2>/dev/null"',
        timeout: const Duration(seconds: 6),
      );
      final lines = const LineSplitter()
          .convert(out)
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final blocked = lines.any((l) {
        final lower = l.toLowerCase();
        return lower.contains('not debuggable') ||
            lower.contains('permission denied') ||
            lower.contains('run-as:');
      });
      if (!blocked) {
        for (final line in lines) {
          if (!line.endsWith('.db') &&
              !line.endsWith('.sqlite') &&
              !line.endsWith('.sqlite3')) {
            continue;
          }
          final remote = '/data/data/$pkg/databases/$line';
          byPath[remote] = DeviceDatabase(
            name: line,
            remotePath: remote,
            access: DbAccess.runAs,
            packageName: pkg,
          );
        }
      }
    } catch (_) {}

    if (byPath.isEmpty) {
      try {
        final out = await adb.shell(
          serial,
          'su -c "ls /data/data/${pkg.replaceAll("'", "")}/databases 2>/dev/null"',
          timeout: const Duration(seconds: 8),
        );
        for (final line in const LineSplitter().convert(out)) {
          final name = line.trim();
          if (!name.endsWith('.db') &&
              !name.endsWith('.sqlite') &&
              !name.endsWith('.sqlite3')) {
            continue;
          }
          final remote = '/data/data/$pkg/databases/$name';
          byPath.putIfAbsent(
            remote,
            () => DeviceDatabase(
              name: name,
              remotePath: remote,
              access: DbAccess.root,
              packageName: pkg,
            ),
          );
        }
      } catch (_) {}
    }

    // Also pick up public copies under /sdcard that mention the package.
    final safePkg = pkg.replaceAll(RegExp(r'[^a-zA-Z0-9._]'), '');
    if (safePkg.isNotEmpty) {
      try {
        final out = await adb.shell(
          serial,
          'find /sdcard /storage/emulated/0 -type f '
          '\\( -name "*.db" -o -name "*.sqlite" \\) 2>/dev/null '
          '| grep "$safePkg" | head -n 40',
          timeout: const Duration(seconds: 20),
        );
        for (final line in const LineSplitter().convert(out)) {
          final path = line.trim();
          if (path.isEmpty) continue;
          final name = path.split('/').last;
          byPath.putIfAbsent(
            path,
            () => DeviceDatabase(
              name: name,
              remotePath: path,
              access: DbAccess.public,
              packageName: pkg,
            ),
          );
        }
      } catch (_) {}
    }

    final list = byPath.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<String> _ensureLocal(String serial, DeviceDatabase db) async {
    final key = '$serial|${db.remotePath}';
    final existing = _cache[key];
    if (existing != null && File(existing).existsSync()) return existing;

    final dir = await Directory.systemTemp.createTemp('adb_utils_db_');
    final local = '${dir.path}${Platform.pathSeparator}${db.name}';

    switch (db.access) {
      case DbAccess.public:
        final err = await adb.pullFile(serial, db.remotePath, local);
        if (err != null) throw AdbException('拉取数据库失败：$err');
      case DbAccess.runAs:
        final pkg = db.packageName;
        if (pkg == null) throw AdbException('缺少包名，无法 run-as');
        final bytes = await adb.execOutBytes(
          serial,
          ['run-as', pkg, 'cat', db.relativeUnderPackage],
          maxBytes: 128 * 1024 * 1024,
        );
        if (bytes == null || bytes.isEmpty) {
          throw AdbException(
            '无法通过 run-as 读取 ${db.name}（应用可能未开启调试）',
          );
        }
        await File(local).writeAsBytes(bytes, flush: true);
      case DbAccess.root:
        final tmpRemote =
            '/sdcard/Download/.adb_utils_${db.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
        await adb.shell(
          serial,
          'su -c "cp ${adb.shellQuote(db.remotePath)} ${adb.shellQuote(tmpRemote)} && chmod 666 ${adb.shellQuote(tmpRemote)}"',
          timeout: const Duration(seconds: 30),
        );
        final err = await adb.pullFile(serial, tmpRemote, local);
        try {
          await adb.shell(serial, 'rm -f ${adb.shellQuote(tmpRemote)}');
        } catch (_) {}
        if (err != null) throw AdbException('拉取数据库失败：$err');
    }

    if (!File(local).existsSync() || File(local).lengthSync() == 0) {
      throw AdbException('本地数据库为空：${db.name}');
    }

    _cache[key] = local;
    return local;
  }

  Future<List<String>> listTables(String serial, DeviceDatabase db) async {
    final local = await _ensureLocal(serial, db);
    final result = await _runSqlite(
      local,
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;",
    );
    return result.rows.map((r) => r.isNotEmpty ? r.first : '').where((n) => n.isNotEmpty).toList();
  }

  Future<DbQueryResult> query(
    String serial,
    DeviceDatabase db,
    String sql, {
    int? limit,
  }) async {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return DbQueryResult.empty;

    var statement = trimmed;
    if (statement.endsWith(';')) {
      statement = statement.substring(0, statement.length - 1).trim();
    }

    final upper = statement.toUpperCase();
    final isSelect = upper.startsWith('SELECT') ||
        upper.startsWith('WITH') ||
        upper.startsWith('PRAGMA') ||
        upper.startsWith('EXPLAIN');

    if (isSelect && limit != null && !upper.contains(' LIMIT ')) {
      statement = '$statement LIMIT $limit';
    }

    final local = await _ensureLocal(serial, db);
    return _runSqlite(local, '$statement;');
  }

  Future<String> exportCsv(
    String serial,
    DeviceDatabase db,
    String sql,
    String savePath,
  ) async {
    final local = await _ensureLocal(serial, db);
    final sqlite = await _sqlite3();
    final result = await Process.run(
      sqlite,
      ['-header', '-csv', local, sql],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw AdbException(err.isEmpty ? '导出 CSV 失败' : err);
    }
    await File(savePath).writeAsString(result.stdout.toString(), encoding: utf8);
    return savePath;
  }

  Future<DbQueryResult> _runSqlite(String dbPath, String sql) async {
    final sqlite = await _sqlite3();
    final result = await Process.run(
      sqlite,
      ['-json', dbPath, sql],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final err = result.stderr.toString().trim();
    if (result.exitCode != 0) {
      throw AdbException(err.isEmpty ? 'SQL 执行失败' : err);
    }

    final raw = result.stdout.toString().trim();
    if (raw.isEmpty || raw == '[]') {
      // Non-SELECT statements or empty result.
      if (err.isNotEmpty) throw AdbException(err);
      return DbQueryResult.empty;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) return DbQueryResult.empty;
    if (decoded.isEmpty) return DbQueryResult.empty;

    final columns = <String>[];
    final rows = <List<String>>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if (columns.isEmpty) {
        columns.addAll(map.keys);
      }
      rows.add(columns.map((c) {
        final v = map[c];
        if (v == null) return '';
        return '$v';
      }).toList());
    }

    return DbQueryResult(columns: columns, rows: rows);
  }

  void invalidateCache({String? serial, String? remotePath}) {
    if (serial == null && remotePath == null) {
      for (final path in _cache.values) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      _cache.clear();
      return;
    }
    final toRemove = <String>[];
    _cache.forEach((key, path) {
      final parts = key.split('|');
      if (serial != null && parts.isNotEmpty && parts.first != serial) return;
      if (remotePath != null &&
          parts.length > 1 &&
          parts.sublist(1).join('|') != remotePath) {
        return;
      }
      toRemove.add(key);
      try {
        File(path).deleteSync();
      } catch (_) {}
    });
    for (final key in toRemove) {
      _cache.remove(key);
    }
  }
}
