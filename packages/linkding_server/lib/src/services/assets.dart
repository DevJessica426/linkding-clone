import 'dart:io';
import 'dart:typed_data';

import 'package:dust_dart/db.dart';

import '../compat/gzip.dart';
import '../db/assets_repo.dart';
import '../db/rows.dart';
import 'errors.dart';

/// linkding's `services/assets.py`: files attached to bookmarks, kept in
/// the asset folder and gzipped (as Python writes gzip files) unless they
/// already are.
final class AssetService {
  AssetService(this.db, this.folder);

  final Executor db;

  /// linkding's `LD_ASSET_FOLDER`, `data/assets`.
  final String folder;

  static const _maxFilenameLength = 192;

  /// `upload_asset`.
  Future<AssetRow> upload(
    BookmarkRow bookmark,
    String name,
    String contentType,
    Uint8List bytes,
  ) async {
    final now = DateTime.now().toUtc();
    final (stem, extension) = _splitExtension(name);
    final gzipped = contentType != 'application/gzip';
    final filename = assetFilename(
      'upload',
      now,
      stem,
      gzipped ? '${_stripDots(extension)}.gz' : _stripDots(extension),
    );
    final file = File('$folder/$filename');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      gzipped ? pythonGzip(bytes, path: file.path, now: now) : bytes,
    );
    final asset = (await AssetsRepo(db).insert(
      now,
      filename,
      gzipped ? await file.length() : bytes.length,
      'upload',
      contentType,
      name,
      'complete',
      gzipped,
      bookmark.id,
    )).orThrow;
    (await AssetsRepo(db).touchBookmark(bookmark.id, now)).orThrow;
    return asset;
  }

  /// `upload_snapshot`: an HTML page saved elsewhere (the browser
  /// extension's single-file snapshot) becomes the bookmark's latest
  /// snapshot.
  Future<AssetRow> uploadSnapshot(BookmarkRow bookmark, Uint8List html) async {
    final now = DateTime.now().toUtc();
    final filename = assetFilename('snapshot', now, bookmark.url, 'html.gz');
    final file = File('$folder/$filename');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(pythonGzip(html, path: file.path, now: now));
    String two(int n) => n.toString().padLeft(2, '0');
    final asset = (await AssetsRepo(db).insert(
      now,
      filename,
      await file.length(),
      'snapshot',
      'text/html',
      'HTML snapshot from ${two(now.month)}/${two(now.day)}/${now.year}',
      'complete',
      true,
      bookmark.id,
    )).orThrow;
    (await AssetsRepo(
      db,
    ).setLatestSnapshot(bookmark.id, asset.id, now)).orThrow;
    return asset;
  }

  /// `remove_asset`, and the file with it.
  Future<void> remove(AssetRow asset) async {
    (await AssetsRepo(db).delete(asset.id, DateTime.now().toUtc())).orThrow;
    if (asset.file.isEmpty) return;
    final file = File('$folder/${asset.file}');
    if (await file.exists()) await file.delete();
  }

  /// `download_name`: snapshots get an extension, uploads keep their name.
  static String downloadName(AssetRow asset) {
    if (asset.assetType != 'snapshot') return asset.displayName;
    return asset.contentType == 'application/pdf'
        ? '${asset.displayName}.pdf'
        : '${asset.displayName}.html';
  }

  /// The asset's content, unzipped; null when the file is gone.
  Future<List<int>?> read(AssetRow asset) async {
    final file = File('$folder/${asset.file}');
    if (asset.file.isEmpty || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return asset.gzip ? gzip.decode(bytes) : bytes;
  }
}

/// `_generate_asset_filename`: type, time and the name reduced to safe
/// characters, cut so the whole stays within 192 characters.
String assetFilename(
  String assetType,
  DateTime created,
  String name,
  String extension,
) {
  String two(int n) => n.toString().padLeft(2, '0');
  final c = created.toUtc();
  final stamp =
      '${c.year}-${two(c.month)}-${two(c.day)}_'
      '${two(c.hour)}${two(c.minute)}${two(c.second)}';
  final safe = [
    for (final rune in name.runes)
      _isSafe(rune) ? String.fromCharCode(rune) : '_',
  ];
  final fixed = '${assetType}_${stamp}_.$extension'.runes.length;
  final kept = safe.take(
    (AssetService._maxFilenameLength - fixed).clamp(0, safe.length),
  );
  return '${assetType}_${stamp}_${kept.join()}.$extension';
}

bool _isSafe(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5a) ||
    (rune >= 0x61 && rune <= 0x7a) ||
    rune == 0x2d ||
    rune == 0x5f ||
    rune == 0x2e;

/// Python's `os.path.splitext`: the extension starts at the last dot that
/// is not part of the name's leading dots.
(String, String) _splitExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return (name, '');
  var leading = 0;
  while (leading < name.length && name[leading] == '.') {
    leading++;
  }
  if (dot < leading) return (name, '');
  return (name.substring(0, dot), name.substring(dot));
}

String _stripDots(String extension) =>
    extension.replaceFirst(RegExp(r'^\.+'), '');
