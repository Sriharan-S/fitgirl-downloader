// Drives two real torrentd processes through the app's TorrentEngine client:
// one seeds a FitGirl-style repack, the other downloads selected files.
// Runs only when TORRENTD_BIN points at a built engine binary.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fitgirl_mobile_flutter/services/torrent_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final binary = Platform.environment['TORRENTD_BIN'];

  test(
    'downloads selected files of a torrent from another engine',
    () async {
      final tmp = await Directory.systemTemp.createTemp('torrentd-dart-');
      final source = Directory(p.join(tmp.path, 'Game [FitGirl Repack]'));
      await source.create(recursive: true);
      final rnd = Random(1);
      final files = {
        'setup.exe': 200 << 10,
        'fg-01.bin': 2 << 20,
        'fg-02.bin': 2 << 20,
        'fg-selective-french.bin': 1 << 20,
      };
      for (final e in files.entries) {
        await File(
          p.join(source.path, e.key),
        ).writeAsBytes(List.generate(e.value, (_) => rnd.nextInt(256)));
      }
      final torrentFile = p.join(tmp.path, 'game.torrent');
      final made = await Process.run(binary!, [
        'mktorrent',
        source.path,
        torrentFile,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      final torrentB64 = base64Encode(await File(torrentFile).readAsBytes());

      final seeder = TorrentEngine.custom(
        binary: binary,
        dataDir: p.join(tmp.path, 'seed-state'),
      );
      final leecher = TorrentEngine.custom(
        binary: binary,
        dataDir: p.join(tmp.path, 'leech-state'),
      );
      addTearDown(() async {
        await seeder.stop();
        await leecher.stop();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });

      // Seeder: existing complete data, all files selected, seeding on.
      await seeder.setSeeding(true);
      final hash = await seeder.add(
        torrentBase64: torrentB64,
        saveDir: source.path,
      );
      final all = (await seeder.get(hash)).files.map((f) => f.index).toList();
      await seeder.selectFiles(hash, all);

      // Leecher: pick everything except the French pack.
      final saveDir = p.join(tmp.path, 'FitGirl_Games', 'Game');
      expect(
        await leecher.add(torrentBase64: torrentB64, saveDir: saveDir),
        hash,
      );
      final status = await leecher.get(hash);
      expect(status.hasMetadata, isTrue);
      expect(status.state, 'waiting');
      final wanted = [
        for (final f in status.files)
          if (!f.path.contains('selective')) f.index,
      ];
      await leecher.selectFiles(hash, wanted);
      await leecher.addPeers(hash, ['127.0.0.1:${await seeder.peerPort()}']);

      final deadline = DateTime.now().add(const Duration(seconds: 90));
      TorrentStatus st;
      do {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        st = await leecher.get(hash);
      } while (st.state != 'completed' && DateTime.now().isBefore(deadline));
      expect(st.state, 'completed');
      expect(st.bytesCompleted, st.length);

      for (final f in st.files) {
        final target = File(p.join(saveDir, f.path));
        if (f.selected) {
          expect(
            await target.readAsBytes(),
            await File(p.join(source.path, f.path)).readAsBytes(),
            reason: f.path,
          );
        } else {
          expect(f.bytesCompleted, lessThan(f.length), reason: f.path);
        }
      }
    },
    skip: binary == null ? 'Set TORRENTD_BIN to run' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
