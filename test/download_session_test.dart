import 'dart:convert';

import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:flutter_test/flutter_test.dart';

const _ff = 'https://fuckingfast.co/abc';

DownloadSession _session(List<DownloadFile> files, {bool paused = false}) =>
    DownloadSession(
      gameTitle: 'Game',
      coverUrl: '',
      files: files,
      createdAt: DateTime(2026),
      isPaused: paused,
    );

void main() {
  group('format', () {
    test('fileNameFromUrl prefers the fragment', () {
      expect(
        fileNameFromUrl('$_ff#Game--fitgirl-repack.part01.rar'),
        'Game--fitgirl-repack.part01.rar',
      );
      expect(
        fileNameFromUrl('https://x.com/a/setup%20file.bin'),
        'setup file.bin',
      );
    });

    test('parseSizeToBytes handles FitGirl size strings', () {
      expect(
        parseSizeToBytes('from 51.1 GB'),
        (51.1 * 1024 * 1024 * 1024).round(),
      );
      expect(parseSizeToBytes('1,5 GB'), (1.5 * 1024 * 1024 * 1024).round());
      expect(parseSizeToBytes('800 MB'), 800 * 1024 * 1024);
      expect(parseSizeToBytes('TBD'), -1);
      expect(parseSizeToBytes(null), -1);
    });

    test('formatBytes / formatSpeed / formatDuration', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatSpeed(0.5), '512 KB/s');
      expect(formatSpeed(12.34), '12.3 MB/s');
      expect(formatDuration(const Duration(minutes: 90)), '1h 30m');
      expect(formatDuration(null), '--');
    });

    test('sanitizeFileName strips characters Windows rejects', () {
      expect(sanitizeFileName('a:b?c*.rar'), 'a_b_c_.rar');
      expect(sanitizeFileName('name. '), 'name');
    });
  });

  group('DownloadSession', () {
    test('status is derived from files', () {
      expect(
        _session([const DownloadFile(url: '1', name: '1')]).status,
        SessionStatus.queued,
      );
      expect(
        _session([
          const DownloadFile(
            url: '1',
            name: '1',
            status: FileStatus.downloading,
          ),
        ]).status,
        SessionStatus.downloading,
      );
      expect(
        _session([
          const DownloadFile(url: '1', name: '1'),
        ], paused: true).status,
        SessionStatus.paused,
      );
      expect(
        _session([
          const DownloadFile(url: '1', name: '1', status: FileStatus.completed),
          const DownloadFile(url: '2', name: '2', status: FileStatus.failed),
        ]).status,
        SessionStatus.failed,
      );
      expect(
        _session([
          const DownloadFile(url: '1', name: '1', status: FileStatus.completed),
        ]).status,
        SessionStatus.completed,
      );
    });

    test('progress, bytes and ETA', () {
      const gb = 1024 * 1024 * 1024;
      final s = _session([
        const DownloadFile(
          url: '1',
          name: '1',
          status: FileStatus.completed,
          expectedSize: gb,
        ),
        const DownloadFile(
          url: '2',
          name: '2',
          status: FileStatus.downloading,
          progress: 0.5,
          expectedSize: gb,
          speed: 10,
        ),
        const DownloadFile(url: '3', name: '3'), // size unknown -> estimated
      ]);
      expect(s.overallProgress, closeTo(0.5, 1e-9));
      expect(s.estimatedTotalBytes, 3 * gb);
      expect(s.downloadedBytes, (1.5 * gb).round());
      expect(s.networkSpeed, 10);
      // 1.5 GB left at 10 MB/s
      expect(s.eta!.inSeconds, closeTo(153.6, 1));
    });

    test('negative progress values never leak into the overall progress', () {
      final s = _session([
        const DownloadFile(url: '1', name: '1', progress: -5),
        const DownloadFile(url: '2', name: '2', status: FileStatus.completed),
      ]);
      expect(s.overallProgress, 0.5);
    });

    test('JSON round-trip keeps per-file state', () {
      final s = _session([
        const DownloadFile(
          url: '$_ff#a.rar',
          name: 'a.rar',
          status: FileStatus.paused,
          taskId: 't1',
          progress: 0.25,
          expectedSize: 100,
          attempts: 2,
          error: 'HTTP 500',
        ),
      ]);
      final back = DownloadSession.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      final f = back.files.single;
      expect(f.status, FileStatus.paused);
      expect(f.taskId, 't1');
      expect(f.progress, 0.25);
      expect(f.expectedSize, 100);
      expect(f.attempts, 2);
      expect(f.error, 'HTTP 500');
    });

    test('migrates sessions saved by the previous app version', () {
      final legacy = {
        'gameTitle': 'Old Game',
        'coverUrl': 'cover',
        'pendingUrls': ['u3', 'u4'],
        'completedUrls': ['u1'],
        'activeTaskIds': ['task-x'],
        'totalFiles': 4, // u2 was in flight
        'totalGameSize': '10 GB',
        'originalUrls': ['u1', 'u2', 'u3', 'u4', 'u5'],
      };
      final s = DownloadSession.fromJson(legacy);
      expect(s.files.map((f) => f.url), ['u1', 'u2', 'u3', 'u4']);
      expect(s.files.first.status, FileStatus.completed);
      expect(
        s.files.skip(1).every((f) => f.status == FileStatus.queued),
        isTrue,
      );
      expect(s.originalUrls.length, 5);
      expect(s.totalGameSize, '10 GB');
    });
  });
}
