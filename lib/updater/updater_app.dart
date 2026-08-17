import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'updater_args.dart';

Future<void> runUpdaterApp(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppColors.apply(Brightness.dark);

  final parsed = UpdaterArgs.parse(args);
  runApp(UpdaterApp(args: parsed));
}

class UpdaterApp extends StatelessWidget {
  const UpdaterApp({super.key, required this.args});

  final UpdaterArgs? args;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB 工具 - 正在更新',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121415),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF006494),
          surface: Color(0xFF1A1C1D),
        ),
      ),
      home: args == null
          ? const _UpdaterErrorPage(
              message: '更新参数无效。请从主程序的「检查更新」重新安装。',
            )
          : UpdaterPage(args: args!),
    );
  }
}

class _UpdaterErrorPage extends StatelessWidget {
  const _UpdaterErrorPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppColors.warning),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => exit(1),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UpdaterPage extends StatefulWidget {
  const UpdaterPage({super.key, required this.args});

  final UpdaterArgs args;

  @override
  State<UpdaterPage> createState() => _UpdaterPageState();
}

class _UpdaterPageState extends State<UpdaterPage> {
  double _progress = 0;
  String _status = '准备更新…';
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final args = widget.args;
    try {
      setState(() {
        _status = '等待主程序退出…';
        _progress = 0.02;
      });
      await _waitForProcess(args.waitPid);

      setState(() {
        _status = '释放被占用的文件…';
        _progress = 0.04;
      });
      await _releaseLockedBinaries(args.installDir);

      setState(() {
        _status = '正在安装文件…';
        _progress = 0.05;
      });

      await _copyDirectoryWithProgress(
        sourceDir: args.sourceDir,
        destDir: args.installDir,
        onProgress: (p, current, total) {
          if (!mounted) return;
          setState(() {
            _progress = 0.05 + p * 0.9;
            _status = total <= 0
                ? '正在安装文件…'
                : '正在安装文件… $current / $total';
          });
        },
      );

      setState(() {
        _status = '正在启动应用…';
        _progress = 0.98;
      });

      await Process.start(
        args.exePath,
        const [],
        mode: ProcessStartMode.detached,
        workingDirectory: args.installDir,
      );

      setState(() {
        _done = true;
        _progress = 1;
        _status = '更新完成';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      exit(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _status = '更新失败';
      });
    }
  }

  /// Stop adb server / leftover processes that lock platform-tools\*.exe.
  Future<void> _releaseLockedBinaries(String installDir) async {
    final adb = File(
      '$installDir${Platform.pathSeparator}platform-tools${Platform.pathSeparator}adb.exe',
    );
    if (adb.existsSync()) {
      try {
        await Process.run(adb.path, ['kill-server']);
      } catch (_) {}
    }
    for (final name in ['adb.exe']) {
      try {
        await Process.run('taskkill', ['/F', '/IM', name, '/T']);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _waitForProcess(int processId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isPidRunning(processId)) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<bool> _isPidRunning(int processId) async {
    try {
      final result = await Process.run(
        'tasklist',
        ['/FI', 'PID eq $processId', '/FO', 'CSV', '/NH'],
      );
      final out = result.stdout.toString().trim();
      if (out.isEmpty || out.toUpperCase().startsWith('INFO:')) return false;
      return RegExp(',"$processId"').hasMatch(out) ||
          RegExp(',$processId,').hasMatch(out);
    } catch (_) {
      return false;
    }
  }

  Future<void> _copyDirectoryWithProgress({
    required String sourceDir,
    required String destDir,
    required void Function(double progress, int current, int total) onProgress,
  }) async {
    final srcRoot = Directory(sourceDir);
    if (!srcRoot.existsSync()) {
      throw StateError('找不到更新文件目录：$sourceDir');
    }
    Directory(destDir).createSync(recursive: true);

    final files = <File>[];
    await for (final entity in srcRoot.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    if (files.isEmpty) {
      throw StateError('更新包为空');
    }

    var totalBytes = 0;
    final sizes = <int>[];
    for (final file in files) {
      final len = file.lengthSync();
      sizes.add(len);
      totalBytes += len;
    }

    var copiedBytes = 0;
    final srcPrefix = srcRoot.path.endsWith(Platform.pathSeparator)
        ? srcRoot.path
        : '${srcRoot.path}${Platform.pathSeparator}';

    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      final relative = file.path.substring(srcPrefix.length);
      final target = File(
        '$destDir${Platform.pathSeparator}$relative',
      );
      target.parent.createSync(recursive: true);

      Object? lastError;
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          await _copyFileOverwrite(file, target);
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          // adb.exe may still be locked briefly after kill-server.
          if (relative.toLowerCase().contains('adb.exe') && attempt == 1) {
            await _releaseLockedBinaries(destDir);
          }
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        }
      }
      if (lastError != null) {
        throw StateError('无法写入 $relative\n$lastError');
      }

      copiedBytes += sizes[i];
      final p = totalBytes == 0 ? 1.0 : copiedBytes / totalBytes;
      onProgress(p.clamp(0.0, 1.0), i + 1, files.length);
    }
  }

  /// Dart [File.copy] fails if the destination already exists (errno 183).
  Future<void> _copyFileOverwrite(File source, File target) async {
    if (target.existsSync()) {
      try {
        target.deleteSync();
      } catch (_) {
        // Fall through — write may still succeed after retry/kill.
      }
    }
    try {
      await source.copy(target.path);
    } catch (_) {
      // Fallback when copy still refuses overwrite / locked briefly.
      final bytes = await source.readAsBytes();
      await target.writeAsBytes(bytes, flush: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ADB 桌面工具',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _error != null ? 0 : (_progress <= 0 ? null : _progress),
                    minHeight: 10,
                    backgroundColor: AppColors.chip,
                    color: _error != null ? AppColors.warning : AppColors.accentBright,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _error != null
                      ? '失败'
                      : '${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => exit(1),
                    child: const Text('关闭'),
                  ),
                ],
                if (_done) ...[
                  const SizedBox(height: 16),
                  Text(
                    '即将打开新版本…',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
