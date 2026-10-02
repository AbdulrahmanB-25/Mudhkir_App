import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/ids.dart';
import '../../core/utils/log.dart';

/// Medication photos kept in the app's private documents folder, so they
/// work offline. Replaces the old ImgBB upload.
class ImageStore {
  ImageStore({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDirectory;

  Future<Directory> _dir() async {
    final dir = Directory(
      p.join((await _baseDirectory()).path, 'medication_images'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies a picked photo into app storage and returns its new path.
  Future<String> saveCopy(String sourcePath) async {
    final extension = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    final target = p.join((await _dir()).path, '${newId()}$extension');
    await File(sourcePath).copy(target);
    return target;
  }

  /// Saves downloaded bytes (a photo synced from another device).
  Future<String> saveBytes(Uint8List bytes, {String extension = '.jpg'}) async {
    final target = p.join((await _dir()).path, '${newId()}$extension');
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  Future<void> deleteLocal(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      log('ImageStore', 'Could not delete $path', e);
    }
  }

  static bool exists(String? path) => path != null && File(path).existsSync();
}
