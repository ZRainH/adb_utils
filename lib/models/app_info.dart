enum AppFilter { user, system, disabled }

class AppInfo {
  const AppInfo({
    required this.name,
    required this.packageName,
    required this.version,
    required this.sizeLabel,
    required this.filter,
    this.iconAsset,
    this.apkPath,
  });

  final String name;
  final String packageName;
  final String version;
  final String sizeLabel;
  final AppFilter filter;
  final String? iconAsset;
  final String? apkPath;

  AppInfo copyWith({
    String? name,
    String? packageName,
    String? version,
    String? sizeLabel,
    AppFilter? filter,
    String? iconAsset,
    String? apkPath,
  }) {
    return AppInfo(
      name: name ?? this.name,
      packageName: packageName ?? this.packageName,
      version: version ?? this.version,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      filter: filter ?? this.filter,
      iconAsset: iconAsset ?? this.iconAsset,
      apkPath: apkPath ?? this.apkPath,
    );
  }
}
