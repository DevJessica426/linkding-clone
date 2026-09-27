import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A gzip file as Python's `gzip.open(path, "wb", compresslevel=9)` writes
/// it: the original file name (the path's base name without `.gz`) and the
/// time in the header, so a file stored here has the size linkding's would.
Uint8List pythonGzip(List<int> data, {required String path, DateTime? now}) {
  var name = path.split('/').last;
  if (name.endsWith('.gz')) name = name.substring(0, name.length - 3);
  final nameBytes = latin1.encode(
    String.fromCharCodes(name.runes.where((r) => r < 256)),
  );
  final mtime = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final header = BytesBuilder(copy: false)
    ..add([0x1f, 0x8b, 0x08, nameBytes.isEmpty ? 0 : 0x08])
    ..add(_uint32(mtime))
    ..add([0x02, 0xff]);
  if (nameBytes.isNotEmpty) {
    header
      ..add(nameBytes)
      ..addByte(0);
  }
  return (BytesBuilder(copy: false)
        ..add(header.takeBytes())
        ..add(ZLibCodec(raw: true, level: 9).encode(data))
        ..add(_uint32(_crc32(data)))
        ..add(_uint32(data.length)))
      .takeBytes();
}

List<int> _uint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 == 1 ? 0xedb88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return crc ^ 0xffffffff;
}
