enum FileKind { folder, image, apk, text, other }

class FileEntry {
  const FileEntry({
    required this.name,
    required this.kind,
    required this.sizeLabel,
    required this.modified,
    required this.path,
  });

  final String name;
  final FileKind kind;
  final String sizeLabel;
  final String modified;
  final String path;

  bool get isDirectory => kind == FileKind.folder;
}
