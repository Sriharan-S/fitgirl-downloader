import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TorrentFileInfo {
  final int index;
  final String path;
  final int length;
  final int bytesCompleted;
  final bool selected;

  const TorrentFileInfo({
    required this.index,
    required this.path,
    required this.length,
    required this.bytesCompleted,
    required this.selected,
  });

  factory TorrentFileInfo.fromJson(Map<String, dynamic> j) => TorrentFileInfo(
    index: (j['index'] as num).toInt(),
    path: j['path'] as String? ?? '',
    length: (j['length'] as num?)?.toInt() ?? 0,
    bytesCompleted: (j['bytesCompleted'] as num?)?.toInt() ?? 0,
    selected: j['selected'] as bool? ?? false,
  );
}

class TorrentStatus {
  final String infoHash;
  final String name;
  final bool hasMetadata;

  /// metadata | waiting | downloading | paused | seeding | completed
  final String state;
  final int length; // Selected files
  final int bytesCompleted; // Selected files
  final double downloadRate; // bytes/s
  final double uploadRate;
  final int peers;
  final int seeders;
  final int knownPeers;
  final List<TorrentFileInfo> files;

  const TorrentStatus({
    required this.infoHash,
    required this.name,
    required this.hasMetadata,
    required this.state,
    required this.length,
    required this.bytesCompleted,
    required this.downloadRate,
    required this.uploadRate,
    required this.peers,
    required this.seeders,
    required this.knownPeers,
    required this.files,
  });

  factory TorrentStatus.fromJson(Map<String, dynamic> j) => TorrentStatus(
    infoHash: j['infoHash'] as String,
    name: j['name'] as String? ?? '',
    hasMetadata: j['hasMetadata'] as bool? ?? false,
    state: j['state'] as String? ?? 'metadata',
    length: (j['length'] as num?)?.toInt() ?? 0,
    bytesCompleted: (j['bytesCompleted'] as num?)?.toInt() ?? 0,
    downloadRate: (j['downloadRate'] as num?)?.toDouble() ?? 0,
    uploadRate: (j['uploadRate'] as num?)?.toDouble() ?? 0,
    peers: (j['peers'] as num?)?.toInt() ?? 0,
    seeders: (j['seeders'] as num?)?.toInt() ?? 0,
    knownPeers: (j['knownPeers'] as num?)?.toInt() ?? 0,
    files: [
      for (final f in (j['files'] as List<dynamic>? ?? const []))
        TorrentFileInfo.fromJson(Map<String, dynamic>.from(f as Map)),
    ],
  );

  bool get isDone => state == 'completed' || state == 'seeding';
}

class TorrentEngineException implements Exception {
  final String message;
  const TorrentEngineException(this.message);
  @override
  String toString() => message;
}

/// Runs the bundled `torrentd` engine (Go, anacrolix/torrent) as a child
/// process and talks to it over a token-protected API on 127.0.0.1.
/// The engine keeps its own state, so torrents survive app restarts.
class TorrentEngine {
  static final TorrentEngine _instance = TorrentEngine._internal();
  factory TorrentEngine() => _instance;
  TorrentEngine._internal() : _binaryOverride = null, _dataDirOverride = null;

  /// A separate engine with an explicit binary and data folder (tests).
  @visibleForTesting
  TorrentEngine.custom({required String binary, required String dataDir})
    : _binaryOverride = binary,
      _dataDirOverride = dataDir;

  final String? _binaryOverride;
  final String? _dataDirOverride;

  static const _channel = MethodChannel('fitgirl/native');

  Process? _process;
  int? _port;
  late final String _token = _randomToken();
  Future<void>? _starting;
  final _http = http.Client();

  /// Platforms that ship the engine. 32-bit Android is not supported.
  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS);

  bool get isRunning => _process != null && _port != null;

  /// Path of the engine binary for this platform, or null if not bundled.
  Future<String?> binaryPath() async {
    if (_binaryOverride != null) return _binaryOverride;
    if (!isSupportedPlatform) return null;
    String path;
    if (Platform.isAndroid) {
      final dir = await _channel.invokeMethod<String>('nativeLibraryDir');
      if (dir == null) return null;
      path = p.join(dir, 'libtorrentd.so');
    } else {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      path = p.join(exeDir, Platform.isWindows ? 'torrentd.exe' : 'torrentd');
    }
    return File(path).existsSync() ? path : null;
  }

  Future<bool> get isAvailable async => await binaryPath() != null;

  Future<void> ensureStarted() {
    if (isRunning) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final binary = await binaryPath();
    if (binary == null) {
      throw const TorrentEngineException(
        'The torrent engine is not available on this device',
      );
    }
    final dataDir =
        _dataDirOverride ??
        p.join((await getApplicationSupportDirectory()).path, 'torrents');
    await Directory(dataDir).create(recursive: true);

    final process = await Process.start(binary, [
      '-data',
      dataDir,
      '-token',
      _token,
    ]);
    final ready = Completer<int>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final m = RegExp(r'^READY (\d+)').firstMatch(line);
          if (m != null && !ready.isCompleted) {
            ready.complete(int.parse(m.group(1)!));
          }
        });
    process.stderr
        .transform(utf8.decoder)
        .listen((s) => debugPrint('torrentd: ${s.trim()}'));
    process.exitCode.then((code) {
      debugPrint('torrentd exited with $code');
      if (identical(_process, process)) {
        _process = null;
        _port = null;
      }
      if (!ready.isCompleted) {
        ready.completeError(
          TorrentEngineException('Torrent engine stopped (exit code $code)'),
        );
      }
    });

    _port = await ready.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        process.kill();
        throw const TorrentEngineException('Torrent engine did not start');
      },
    );
    _process = process;
  }

  /// Stops the engine (it saves its state first).
  Future<void> stop() async {
    final process = _process;
    _process = null;
    _port = null;
    if (process == null) return;
    await process.stdin.close(); // The engine exits when stdin closes
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------

  Future<String> add({
    String? magnet,
    String? torrentUrl,
    String? torrentBase64,
    required String saveDir,
  }) async {
    final res = await _call('POST', '/torrents', {
      'magnet': ?magnet,
      'torrentUrl': ?torrentUrl,
      'torrentBase64': ?torrentBase64,
      'saveDir': saveDir,
    });
    return res['infoHash'] as String;
  }

  Future<TorrentStatus> get(String infoHash) async =>
      TorrentStatus.fromJson(await _call('GET', '/torrents/$infoHash'));

  Future<List<TorrentStatus>> list({bool withFiles = false}) async {
    final res = await _call('GET', '/torrents${withFiles ? '?files=1' : ''}');
    return [
      for (final t in res as List<dynamic>)
        TorrentStatus.fromJson(Map<String, dynamic>.from(t as Map)),
    ];
  }

  Future<void> selectFiles(String infoHash, List<int> indexes) =>
      _call('POST', '/torrents/$infoHash/files', {'selected': indexes});

  /// Connects a torrent to specific peers ("host:port").
  Future<void> addPeers(String infoHash, List<String> peers) =>
      _call('POST', '/torrents/$infoHash/peers', {'peers': peers});

  /// The BitTorrent port other clients connect to.
  Future<int> peerPort() async =>
      ((await _call('GET', '/health'))['peerPort'] as num).toInt();

  Future<void> pause(String infoHash) =>
      _call('POST', '/torrents/$infoHash/pause');

  Future<void> resume(String infoHash) =>
      _call('POST', '/torrents/$infoHash/resume');

  Future<void> remove(String infoHash, {bool deleteFiles = false}) => _call(
    'DELETE',
    '/torrents/$infoHash${deleteFiles ? '?deleteFiles=1' : ''}',
  );

  Future<void> setSeeding(bool seed) =>
      _call('POST', '/settings', {'seed': seed});

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    await ensureStarted();
    final request = http.Request(
      method,
      Uri.parse('http://127.0.0.1:$_port$path'),
    )..headers['X-Token'] = _token;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 90)),
    );
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final message = decoded is Map ? decoded['error'] : res.body;
      throw TorrentEngineException('$message');
    }
    return decoded;
  }

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(
      32,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
