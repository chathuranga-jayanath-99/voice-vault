import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voice_vault/models/recording.dart';
import 'package:voice_vault/services/recording_service.dart';

void main() {
  late Directory tempDir;
  late RecordingService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice_vault_test_');
    RecordingService.directoryProvider = () async => tempDir;
    service = RecordingService();
  });

  tearDown(() async {
    RecordingService.directoryProvider = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Recording rec(String id, {String name = 'r', int ms = 1000}) => Recording(
        id: id,
        name: name,
        filePath: '/tmp/$id.m4a',
        createdAt: DateTime.utc(2026, 1, 1),
        durationMs: ms,
      );

  group('RecordingService.save + load round-trip', () {
    test('returns empty list when no file exists', () async {
      expect(await service.load(), isEmpty);
    });

    test('persists and rehydrates a single recording', () async {
      await service.save([rec('a')]);
      final loaded = await service.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'a');
      expect(loaded.single.name, 'r');
      expect(loaded.single.filePath, '/tmp/a.m4a');
      expect(loaded.single.durationMs, 1000);
    });

    test('persists multiple recordings in order', () async {
      await service.save([rec('a'), rec('b'), rec('c')]);
      final loaded = await service.load();
      expect(loaded.map((r) => r.id), ['a', 'b', 'c']);
    });

    test('overwrites previous save', () async {
      await service.save([rec('a'), rec('b')]);
      await service.save([rec('c')]);
      expect((await service.load()).map((r) => r.id), ['c']);
    });
  });

  group('Atomic write', () {
    test('no .tmp file remains after a successful save', () async {
      await service.save([rec('a')]);
      final leftover = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'))
          .toList();
      expect(leftover, isEmpty);
    });

    test('leaves previous file intact when new save fails', () async {
      await service.save([rec('original')]);

      // Sabotage: replace _metaFile with read-only permissions on disk.
      // We simulate a write failure by making the directory read-only.
      if (Platform.isWindows) {
        // On Windows, removing write perms on a dir is non-trivial; instead
        // simulate by writing a file in place of the directory.
        // The simpler check: just verify rename is atomic by inspecting the
        // file mid-flight would require a hook — instead we check that the
        // previous good state survives a forced throw.
        // Skip Windows-specific perm test.
        return;
      }
      // POSIX: chmod directory to read-only, attempt a save, then restore.
      await Process.run('chmod', ['-w', tempDir.path]);
      Object? caught;
      try {
        try {
          await service.save([rec('new')]);
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<StorageException>(),
            reason: 'read-only dir should produce StorageException');
        // Original file is intact.
        final still = await service.load();
        expect(still.map((r) => r.id), ['original']);
      } finally {
        await Process.run('chmod', ['u+w', tempDir.path]);
      }
    });
  });

  group('Corrupt file self-heal', () {
    test('quarantines corrupt JSON and throws StorageException', () async {
      final file = File('${tempDir.path}/metadata.json');
      await file.writeAsString('{not valid json');

      Object? caught;
      try {
        await service.load();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StorageException>());
      expect((caught as StorageException).message, contains('quarantined'));

      // Original file moved aside.
      expect(file.existsSync(), isFalse);
      final backups = tempDir
          .listSync()
          .where((e) =>
              RegExp(r'metadata\.json\.corrupt\.\d+$').hasMatch(e.path))
          .toList();
      expect(backups, hasLength(1));
    });

    test('quarantined file still contains the original bytes', () async {
      final file = File('${tempDir.path}/metadata.json');
      const originalContents = '{not valid json';
      await file.writeAsString(originalContents);

      try {
        await service.load();
      } catch (_) {}

      final backups = tempDir
          .listSync()
          .where((e) => RegExp(r'metadata\.json\.corrupt\.\d+$').hasMatch(e.path))
          .toList();
      expect(backups, hasLength(1));
      final backed = await File(backups.single.path).readAsString();
      expect(backed, originalContents);
    });

    test('successful save proceeds after a corrupt file is quarantined', () async {
      final file = File('${tempDir.path}/metadata.json');
      await file.writeAsString('garbage');
      try {
        await service.load();
      } catch (_) {}

      // Save should succeed with no leftover .tmp.
      await service.save([rec('recovered')]);
      expect(await service.load(), hasLength(1));
    });
  });

  group('Recording JSON round-trip', () {
    test('toJson / fromJson are inverses', () async {
      final original = Recording(
        id: 'x',
        name: 'name with "quotes"',
        filePath: '/p/x.m4a',
        createdAt: DateTime.utc(2026, 7, 4, 12, 30),
        durationMs: 12345,
      );
      final restored = Recording.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.filePath, original.filePath);
      expect(restored.createdAt, original.createdAt);
      expect(restored.durationMs, original.durationMs);
    });
  });
}