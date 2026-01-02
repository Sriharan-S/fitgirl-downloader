import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';

class FavoritesService {
  static final FavoritesService _instance = FavoritesService._internal();

  factory FavoritesService() {
    return _instance;
  }

  FavoritesService._internal() {
    _loadInitial();
  }

  static const String _key = 'favorite_games';
  final ValueNotifier<List<Game>> favoritesNotifier = ValueNotifier([]);

  Future<void> _loadInitial() async {
    favoritesNotifier.value = await getFavorites();
  }

  Future<List<Game>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_key) ?? [];
    try {
      return list.map((item) => Game.fromJson(jsonDecode(item))).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addFavorite(Game game) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_key) ?? [];

    // Check if already exists by checking URL
    bool exists = false;
    for (var item in list) {
      try {
        if (Game.fromJson(jsonDecode(item)).url == game.url) {
          exists = true;
          break;
        }
      } catch (e) {
        // ignore parsing errors
      }
    }

    if (!exists) {
      list.add(jsonEncode(game.toJson()));
      await prefs.setStringList(_key, list);
      favoritesNotifier.value = await getFavorites();
    }
  }

  Future<void> removeFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_key) ?? [];

    list.removeWhere((item) {
      try {
        return Game.fromJson(jsonDecode(item)).url == url;
      } catch (e) {
        return false;
      }
    });

    await prefs.setStringList(_key, list);
    favoritesNotifier.value = await getFavorites();
  }

  Future<bool> isFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_key) ?? [];
    return list.any((item) {
      try {
        return Game.fromJson(jsonDecode(item)).url == url;
      } catch (e) {
        return false;
      }
    });
  }
}
