enum FileKind { folder, image, apk, text, log, json, other }

class FileEntry {
  const FileEntry({
    required this.name,
    required this.kind,
    required this.sizeLabel,
    required this.modified,
    required this.path,
    this.sizeBytes = 0,
  });

  final String name;
  final FileKind kind;
  final String sizeLabel;
  final String modified;
  final String path;
  final int sizeBytes;

  bool get isDirectory => kind == FileKind.folder;

  bool get isPreviewable =>
      kind == FileKind.text ||
      kind == FileKind.image ||
      kind == FileKind.log ||
      kind == FileKind.json;
}
