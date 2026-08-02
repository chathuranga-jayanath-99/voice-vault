import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../models/recording.dart';

/// Thrown when a persistence operation fails. Caller is responsible for
/// surfacing [message] to the user; the service has already taken whatever
/// self-heal action it can.
class StorageException implements Exception {
  final String message;
  final Object? cause;
  StorageException(this.message, [this.cause]);

  @override
  String toString() =>
      'StorageException: $message${cause == null ? '' : ' ($cause)'}';
}

class RecordingService {
  static const _metaFile = 'metadata.json';
  static const _tmpSuffix = '.tmp';

  /// Override for tests. When null, uses [getApplicationDocumentsDirectory].
  static Future<Directory> Function()? directoryProvider;

  static Future<Directory> _defaultDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/voice_vault_recordings');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _getDir() async {
    final provider = directoryProvider;
    if (provider != null) return provider();
    return _defaultDir();
  }

  /// Loads persisted recordings. Web recordings are session-only.
  ///
  /// On a corrupt [metadata.json], the bad file is **backed up** with a
  /// timestamp suffix before being discarded, so the next [save] cannot
  /// overwrite data that might still be recoverable from the backup.
  Future<List<Recording>> load() async {
    if (kIsWeb) return [];
    final dir = await _getDir();
    final file = File('${dir.path}/$_metaFile');
    if (!file.existsSync()) return [];
    final raw = await file.readAsString().catchError((Object e) {
      throw StorageException('Failed to read metadata file', e);
    });
    if (raw.trim().isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Recording.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Self-heal: quarantine the corrupt file rather than letting the next
      // save() overwrite it with an empty list.
      final backup = '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(backup);
      } catch (renameErr) {
        // If we can't even move it aside, the file may be locked. Surface this.
        throw StorageException(
          'Metadata is corrupt and could not be backed up. '
          'Recordings may be lost on next save.',
          renameErr,
        );
      }
      throw StorageException(
        'Saved recordings index was corrupt and has been quarantined to '
        '"${backup.split(Platform.pathSeparator).last}". '
        'Your audio files are untouched, but they are no longer listed.',
        e,
      );
    }
  }

  /// Persists [recordings] atomically: write to `metadata.json.tmp` then
  /// rename into place. A crash mid-write leaves the previous file intact.
  Future<void> save(List<Recording> recordings) async {
    if (kIsWeb) return;
    final dir = await _getDir();
    final target = File('${dir.path}/$_metaFile');
    final tmp = File('${target.path}$_tmpSuffix');
    final payload = jsonEncode(recordings.map((r) => r.toJson()).toList());
    try {
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(target.path);
    } catch (e) {
      // Best-effort cleanup of the temp file.
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {/* swallow */}
      }
      throw StorageException('Failed to save recordings index', e);
    }
  }

  Future<String> newFilePath() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (kIsWeb) return 'rec_$ts.webm';
    final dir = await _getDir();
    return '${dir.path}/rec_$ts.m4a';
  }

  Future<void> deleteFile(String path) async {
    if (kIsWeb) return;
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}