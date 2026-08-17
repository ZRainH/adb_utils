class UpdaterArgs {
  const UpdaterArgs({
    required this.waitPid,
    required this.sourceDir,
    required this.installDir,
    required this.exePath,
  });

  final int waitPid;
  final String sourceDir;
  final String installDir;
  final String exePath;

  static bool isUpdaterMode(List<String> args) =>
      args.contains('--updater') || args.any((a) => a.startsWith('--updater'));

  static UpdaterArgs? parse(List<String> args) {
    final map = <String, String>{};
    for (final raw in args) {
      if (raw == '--updater') {
        map['updater'] = '1';
        continue;
      }
      if (!raw.startsWith('--')) continue;
      final eq = raw.indexOf('=');
      if (eq <= 2) continue;
      map[raw.substring(2, eq)] = raw.substring(eq + 1);
    }

    final pid = int.tryParse(map['pid'] ?? '');
    final src = map['src']?.trim() ?? '';
    final dst = map['dst']?.trim() ?? '';
    final exe = map['exe']?.trim() ?? '';
    if (pid == null || src.isEmpty || dst.isEmpty || exe.isEmpty) {
      return null;
    }
    return UpdaterArgs(
      waitPid: pid,
      sourceDir: src,
      installDir: dst,
      exePath: exe,
    );
  }
}
