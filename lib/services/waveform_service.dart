import 'dart:convert';
import 'dart:io';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../models/recording.dart';

/// Extracts and caches amplitude peaks for the playback waveform.
///
/// On web, recordings are session-only blob URLs and never re-open, so the
/// waveform is meaningless there — [getOrCompute] returns an empty list.
class WaveformService {
  static const _peaks = 80;

  Future<Directory> _dir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/voice_vault_recordings/waveforms');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  File _cacheFile(Directory dir, Recording rec) =>
      File('${dir.path}/${rec.id}.json');

  Future<List<double>> getOrCompute(Recording rec) async {
    if (kIsWeb) return const [];
    final dir = await _dir();
    final cache = _cacheFile(dir, rec);
    if (cache.existsSync()) {
      try {
        final list = jsonDecode(cache.readAsStringSync()) as List;
        return list.cast<double>();
      } catch (_) {
        // Fall through to recompute on corrupt cache.
      }
    }
    final peaks = await AudioDecoder.getWaveform(
      rec.filePath,
      numberOfSamples: _peaks,
      normalization: WaveformNormalization.perFile,
    ).catchError((_) => <double>[]);
    if (peaks.isNotEmpty) {
      cache.writeAsStringSync(jsonEncode(peaks));
    }
    return peaks;
  }

  Future<void> deleteCache(String id) async {
    if (kIsWeb) return;
    final dir = await _dir();
    final f = File('${dir.path}/$id.json');
    if (f.existsSync()) f.deleteSync();
  }
}
