import 'dart:convert';
import 'dart:io';

import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk cache of scraped data so screens open instantly with what was
/// seen last time, while fresh data loads quietly in the background.
class CacheStore {
  static final CacheStore _instance = CacheStore._internal();
  factory CacheStore() => _instance;
  CacheStore._internal();

  Directory? _dir;
  final Map<String, Game> _games = {};

  Future<Directory?> _root() async {
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'cache'));
      await dir.create(recursive: true);
      return _dir = dir;
    } catch (e) {
      debugPrint('CacheStore unavailable: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Game lists (Discover sections)
  // ---------------------------------------------------------------------------

  Future<List<Game>?> readList(String name) async {
    final data = await _read('list_$name.json');
    if (data is! List) return null;
    try {
      return [
        for (final g in data)
          Game.fromJson(Map<String, dynamic>.from(g as Map)),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writeList(String name, List<Game> games) =>
      _write('list_$name.json', games.map((g) => g.toJson()).toList());

  // ---------------------------------------------------------------------------
  // Game details
  // ---------------------------------------------------------------------------

  /// Last known details of a game page, if any.
  Future<Game?> readGame(String url) async {
    final memory = _games[url];
    if (memory != null) return memory;
    final data = await _read(p.join('games', '${_key(url)}.json'));
    if (data is! Map) return null;
    try {
      return _games[url] = Game.fromJson(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeGame(Game game) async {
    _games[game.url] = game;
    await _write(p.join('games', '${_key(game.url)}.json'), game.toJson());
  }

  // ---------------------------------------------------------------------------

  Future<Object?> _read(String relative) async {
    final dir = await _root();
    if (dir == null) return null;
    try {
      final file = File(p.join(dir.path, relative));
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String relative, Object data) async {
    final dir = await _root();
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, relative));
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('CacheStore write failed: $e');
    }
  }

  /// Stable file-name-safe key for a URL (FNV-1a, 64 bit).
  static String _key(String url) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final unit in utf8.encode(url)) {
      hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}

/// Image cache for covers and screenshots: larger and longer-lived than the
/// default (200 images / 30 days), so browsing doesn't re-download images.
final appImageCache = CacheManager(
  Config(
    'fitgirlImages',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 3000,
  ),
);
