import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum LogLevel {
  verbose,
  debug,
  info,
  warning,
  error;

  static LogLevel? fromName(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final e in values) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// Minimum level for filtering (matches Android Studio Logcat).
  bool passesMinLevel(LogLevel? minLevel) {
    if (minLevel == null) return true;
    return index >= minLevel.index;
  }

  String get chipCode {
    switch (this) {
      case LogLevel.verbose:
        return 'V';
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    this.packageName,
  });

  final String timestamp;
  final String pid;
  final String tid;
  final LogLevel level;
  final String tag;
  final String message;
  final String? packageName;

  LogEntry copyWith({String? packageName}) {
    return LogEntry(
      timestamp: timestamp,
      pid: pid,
      tid: tid,
      level: level,
      tag: tag,
      message: message,
      packageName: packageName ?? this.packageName,
    );
  }

  Color get color {
    switch (level) {
      case LogLevel.verbose:
        return AppColors.verboseLog;
      case LogLevel.debug:
        return AppColors.debugLog;
      case LogLevel.info:
        return AppColors.infoLog;
      case LogLevel.warning:
        return AppColors.warning;
      case LogLevel.error:
        return AppColors.errorLog;
    }
  }

  String get levelCode {
    switch (level) {
      case LogLevel.verbose:
        return 'V';
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  String get fullLine {
    final pkg = packageName;
    final pkgPart = pkg != null && pkg.isNotEmpty ? ' ($pkg)' : '';
    return '$timestamp $pid-$tid $levelCode/$tag:$pkgPart $message';
  }

  bool matches(
    String query,
    LogLevel? minLevel, {
    String? packageFilter,
  }) {
    if (!level.passesMinLevel(minLevel)) return false;

    if (packageFilter != null && packageFilter.isNotEmpty) {
      final want = packageFilter.toLowerCase();
      final pkg = packageName?.toLowerCase() ?? '';
      if (pkg != want) return false;
    }

    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;

    // Support "pkg:com.foo" / "package:com.foo" shortcuts.
    final pkgQuery = q.startsWith('pkg:')
        ? q.substring(4).trim()
        : q.startsWith('package:')
            ? q.substring(8).trim()
            : null;

    if (pkgQuery != null && pkgQuery.isNotEmpty) {
      final pkg = packageName?.toLowerCase() ?? '';
      return pkg.contains(pkgQuery);
    }

    final pkg = packageName?.toLowerCase() ?? '';
    return tag.contains(q) ||
        message.contains(q) ||
        pid.contains(q) ||
        tid.contains(q) ||
        pkg.contains(q);
  }

  /// Faster path when [queryLower] is already lowercased.
  bool matchesFast(String queryLower, LogLevel? minLevel) {
    if (!level.passesMinLevel(minLevel)) return false;
    if (queryLower.isEmpty) return true;

    final pkgQuery = queryLower.startsWith('pkg:')
        ? queryLower.substring(4).trim()
        : queryLower.startsWith('package:')
            ? queryLower.substring(8).trim()
            : null;

    if (pkgQuery != null && pkgQuery.isNotEmpty) {
      final pkg = packageName?.toLowerCase() ?? '';
      return pkg.contains(pkgQuery);
    }

    final pkg = packageName?.toLowerCase() ?? '';
    final tagLower = tag.toLowerCase();
    final msgLower = message.toLowerCase();
    return tagLower.contains(queryLower) ||
        msgLower.contains(queryLower) ||
        pid.contains(queryLower) ||
        tid.contains(queryLower) ||
        pkg.contains(queryLower);
  }
}
