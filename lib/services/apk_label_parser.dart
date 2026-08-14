import 'dart:convert';
import 'dart:typed_data';

/// Reads android:label of `<application>` from binary AndroidManifest.xml,
/// resolving `@string/...` via resources.arsc when needed.
class ApkLabelParser {
  static String? readApplicationLabel(
    Uint8List manifestBytes, {
    Uint8List? resourcesArsc,
    List<Uint8List>? extraResources,
  }) {
    final xml = _BinaryXml.parse(manifestBytes);
    if (xml == null) return null;

    final label = xml.applicationLabel;
    if (label == null) return null;

    if (label.directString != null) {
      return _clean(label.directString!);
    }

    final resId = label.resourceId;
    if (resId == null) return null;

    String? best;
    for (final arsc in [
      ?resourcesArsc,
      ...?extraResources,
    ]) {
      final hit = _ArscResolver(arsc).resolveString(resId);
      if (hit == null) continue;
      if (_isCjk(hit)) return hit;
      best ??= hit;
    }
    return best;
  }
}

String? _clean(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('@')) return null;
  return s;
}

bool _isCjk(String value) =>
    value.runes.any((r) => r >= 0x4e00 && r <= 0x9fff);

class _LabelValue {
  const _LabelValue.string(this.directString) : resourceId = null;
  const _LabelValue.resource(this.resourceId) : directString = null;

  final String? directString;
  final int? resourceId;
}

class _BinaryXml {
  _BinaryXml(this.applicationLabel);

  final _LabelValue? applicationLabel;

  static _BinaryXml? parse(Uint8List data) {
    if (data.length < 8) return null;
    final bd = ByteData.sublistView(data);
    if (bd.getUint16(0, Endian.little) != 0x0003) return null;

    var offset = 8;
    var strings = <String>[];
    _LabelValue? appLabel;

    while (offset + 8 <= data.length) {
      final chunkType = bd.getUint16(offset, Endian.little);
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkSize < 8 || offset + chunkSize > data.length) break;

      switch (chunkType) {
        case 0x0001:
          strings = _parseStringPool(data, offset);
          break;
        case 0x0102:
          final el = _parseStartElement(data, offset, strings);
          if (el.name == 'application') {
            appLabel ??= el.label;
          }
          break;
      }
      offset += chunkSize;
    }

    return _BinaryXml(appLabel);
  }

  static List<String> _parseStringPool(Uint8List data, int offset) {
    final bd = ByteData.sublistView(data);
    final stringCount = bd.getUint32(offset + 8, Endian.little);
    final flags = bd.getUint32(offset + 16, Endian.little);
    final stringsStart = bd.getUint32(offset + 20, Endian.little);
    final isUtf8 = (flags & (1 << 8)) != 0;

    final offsets = <int>[];
    var pos = offset + 28;
    for (var i = 0; i < stringCount; i++) {
      if (pos + 4 > data.length) break;
      offsets.add(bd.getUint32(pos, Endian.little));
      pos += 4;
    }

    final base = offset + stringsStart;
    return [
      for (final off in offsets)
        if (base + off < data.length)
          isUtf8 ? _readUtf8String(data, base + off) : _readUtf16String(data, base + off)
        else
          '',
    ];
  }

  static String _readUtf16String(Uint8List data, int start) {
    final bd = ByteData.sublistView(data);
    if (start + 2 > data.length) return '';
    var charCount = bd.getUint16(start, Endian.little);
    var header = 2;
    if ((charCount & 0x8000) != 0) {
      if (start + 4 > data.length) return '';
      charCount = ((charCount & 0x7fff) << 16) | bd.getUint16(start + 2, Endian.little);
      header = 4;
    }
    final from = start + header;
    if (from + charCount * 2 > data.length) return '';
    return String.fromCharCodes([
      for (var i = 0; i < charCount; i++) bd.getUint16(from + i * 2, Endian.little),
    ]);
  }

  static String _readUtf8String(Uint8List data, int start) {
    if (start >= data.length) return '';
    var pos = start;
    var charLen = data[pos++];
    if ((charLen & 0x80) != 0) {
      if (pos >= data.length) return '';
      charLen = ((charLen & 0x7f) << 8) | data[pos++];
    }
    if (pos >= data.length) return '';
    var byteLen = data[pos++];
    if ((byteLen & 0x80) != 0) {
      if (pos >= data.length) return '';
      byteLen = ((byteLen & 0x7f) << 8) | data[pos++];
    }
    if (pos + byteLen > data.length) return '';
    return utf8.decode(data.sublist(pos, pos + byteLen), allowMalformed: true);
  }

  static _StartElement _parseStartElement(
    Uint8List data,
    int offset,
    List<String> strings,
  ) {
    final bd = ByteData.sublistView(data);
    final nameIdx = bd.getInt32(offset + 20, Endian.little);
    final attributeStart = bd.getUint16(offset + 24, Endian.little);
    final attributeSize = bd.getUint16(offset + 26, Endian.little);
    final attributeCount = bd.getUint16(offset + 28, Endian.little);
    final name = _str(strings, nameIdx);
    _LabelValue? label;

    final attrBase = offset + 16 + attributeStart;
    final stride = attributeSize == 0 ? 20 : attributeSize;
    for (var i = 0; i < attributeCount; i++) {
      final a = attrBase + i * stride;
      if (a + 20 > data.length) break;
      final attrNameIdx = bd.getInt32(a + 4, Endian.little);
      final rawValueIdx = bd.getInt32(a + 8, Endian.little);
      final dataType = data[a + 15];
      final typedData = bd.getUint32(a + 16, Endian.little);
      if (_str(strings, attrNameIdx) != 'label') continue;

      if (dataType == 0x03) {
        final idx = rawValueIdx >= 0 ? rawValueIdx : typedData;
        label = _LabelValue.string(_str(strings, idx));
      } else if (dataType == 0x01) {
        label = _LabelValue.resource(typedData);
      } else if (rawValueIdx >= 0) {
        label = _LabelValue.string(_str(strings, rawValueIdx));
      }
      break;
    }

    return _StartElement(name: name, label: label);
  }

  static String _str(List<String> strings, int index) {
    if (index < 0 || index >= strings.length) return '';
    return strings[index];
  }
}

class _StartElement {
  const _StartElement({required this.name, required this.label});
  final String name;
  final _LabelValue? label;
}

class _ArscResolver {
  _ArscResolver(this.data)
      : bd = ByteData.sublistView(data),
        globalStrings = _BinaryXml._parseStringPool(data, 12);

  final Uint8List data;
  final ByteData bd;
  final List<String> globalStrings;

  String? resolveString(int resId) {
    if (data.length < 12 || bd.getUint16(0, Endian.little) != 0x0002) {
      return null;
    }

    final packageId = (resId >> 24) & 0xff;
    final typeId = (resId >> 16) & 0xff;
    final entryIndex = resId & 0xffff;

    var offset = 12;
    if (offset + 8 <= data.length && bd.getUint16(offset, Endian.little) == 0x0001) {
      offset += bd.getUint32(offset + 4, Endian.little);
    }

    while (offset + 8 <= data.length) {
      final chunkType = bd.getUint16(offset, Endian.little);
      final headerSize = bd.getUint16(offset + 2, Endian.little);
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkSize < 8 || offset + chunkSize > data.length) break;

      if (chunkType == 0x0200) {
        final id = bd.getUint32(offset + 8, Endian.little);
        if (id == packageId) {
          final hit = _resolveInPackage(offset, headerSize, chunkSize, typeId, entryIndex);
          if (hit != null) return hit;
        }
      }
      offset += chunkSize;
    }
    return null;
  }

  String? _resolveInPackage(
    int pkgOff,
    int pkgHeader,
    int pkgSize,
    int typeId,
    int entryIndex,
  ) {
    final keyStringsOff = bd.getUint32(pkgOff + 276, Endian.little);
    final keyPoolSize = bd.getUint32(pkgOff + keyStringsOff + 4, Endian.little);

    var inner = pkgOff + keyStringsOff + keyPoolSize;
    if (inner < pkgOff + pkgHeader) inner = pkgOff + pkgHeader;
    final end = pkgOff + pkgSize;

    String? best;
    var bestScore = -1;
    while (inner + 8 <= end) {
      final t = bd.getUint16(inner, Endian.little);
      final th = bd.getUint16(inner + 2, Endian.little);
      final ts = bd.getUint32(inner + 4, Endian.little);
      if (ts < 8 || inner + ts > end) break;

      // RES_TABLE_TYPE_TYPE = 0x0201 (NOT 0x0202 TYPE_SPEC).
      if (t == 0x0201 && data[inner + 8] == typeId) {
        final flags = data[inner + 9];
        final entryCount = bd.getUint32(inner + 12, Endian.little);
        if (entryIndex < entryCount) {
          final value = (flags & 0x01) != 0
              ? _readSparse(inner, th, entryCount, entryIndex)
              : _readFlat(inner, th, entryCount, entryIndex);
          if (value != null) {
            final score = _localeScore(inner, th, value);
            if (score > bestScore) {
              bestScore = score;
              best = value;
            }
          }
        }
      }
      inner += ts;
    }
    return best;
  }

  int _localeScore(int typeOff, int headerSize, String value) {
    var score = 0;
    if (_isCjk(value)) score += 100;
    if (headerSize >= 48) {
      // ResTable_config: language at +8, country at +10 from config base (+20).
      final lang = String.fromCharCodes([
        data[typeOff + 28],
        data[typeOff + 29],
      ]).replaceAll('\u0000', '');
      final country = String.fromCharCodes([
        data[typeOff + 30],
        data[typeOff + 31],
      ]).replaceAll('\u0000', '');
      if (lang == 'zh') {
        score += 50;
        if (country == 'CN') score += 30;
        if (country == 'TW' || country == 'HK') score += 15;
      } else if (lang == 'en') {
        score += 5;
      } else if (lang.isEmpty) {
        score += 10; // default
      }
    }
    return score;
  }

  String? _readFlat(int typeOff, int headerSize, int entryCount, int entryIndex) {
    if (headerSize < 20) return null;
    final entriesStart = bd.getUint32(typeOff + 16, Endian.little);
    final offPos = typeOff + headerSize + entryIndex * 4;
    if (offPos + 4 > data.length) return null;
    final rel = bd.getInt32(offPos, Endian.little);
    if (rel < 0) return null;
    return _readEntry(typeOff + entriesStart + rel);
  }

  String? _readSparse(int typeOff, int headerSize, int sparseCount, int entryIndex) {
    var lo = 0;
    var hi = sparseCount - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final idx = bd.getUint16(typeOff + headerSize + mid * 4, Endian.little);
      if (idx == entryIndex) {
        final offUnits = bd.getUint16(typeOff + headerSize + mid * 4 + 2, Endian.little);
        return _readEntry(typeOff + offUnits * 4);
      } else if (idx < entryIndex) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  String? _readEntry(int entryPos) {
    if (entryPos + 16 > data.length) return null;
    final flags = bd.getUint16(entryPos + 2, Endian.little);
    if ((flags & 0x0001) != 0) return null; // complex
    final dataType = data[entryPos + 11];
    final typed = bd.getUint32(entryPos + 12, Endian.little);
    if (dataType != 0x03) return null;
    if (typed < 0 || typed >= globalStrings.length) return null;
    return _clean(globalStrings[typed]);
  }
}
