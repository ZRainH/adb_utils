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

  bool matches(String query, LogLevel? filterLevel) {
    if (filterLevel != null && level != filterLevel) return false;
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
    return tag.toLowerCase().contains(q) ||
        message.toLowerCase().contains(q) ||
        pid.contains(q) ||
        tid.contains(q) ||
        pkg.contains(q);
  }
}
