import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../models/recording.dart';

class RecordingService {
  static const _metaFile = 'metadata.json';

  Future<Directory> _getDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/voice_vault_recordings');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // Web recordings are session-only (blob URLs expire on refresh).
  // Mobile recordings persist to the app documents directory.
  Future<List<Recording>> load() async {
    if (kIsWeb) return [];
    final dir = await _getDir();
    final file = File('${dir.path}/$_metaFile');
    if (!file.existsSync()) return [];
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return list
          .map((e) => Recording.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Recording> recordings) async {
    if (kIsWeb) return;
    final dir = await _getDir();
    File('${dir.path}/$_metaFile').writeAsStringSync(
      jsonEncode(recordings.map((r) => r.toJson()).toList()),
    );
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
