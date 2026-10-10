import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:flutter_test/flutter_test.dart';

Game _g(String title, String? genre) => Game(
  id: title,
  title: title,
  url: title,
  coverUrl: '',
  size: '1 GB',
  genre: genre,
);

void main() {
  test('adult games are detected from tags and titles', () {
    expect(_g('Some Visual Novel', 'Adult, Anime, Romance').isNsfw, isTrue);
    expect(_g('SEXNATURAL: MILFs Must Be Filled', 'Casual').isNsfw, isTrue);
    expect(_g('Game, Build 1 + Wallpapers 18+', null).isNsfw, isTrue);
    expect(_g('Hentai Puzzle', 'Puzzle').isNsfw, isTrue);
  });

  test('regular games are not', () {
    expect(_g("Dragon's Dogma 2", 'Action, RPG, Open World').isNsfw, isFalse);
    expect(_g('Grand Theft Auto V', 'Action, Shooter').isNsfw, isFalse);
    expect(_g('Essex Racing', 'Racing').isNsfw, isFalse);
    expect(
      _g('Sextant Navigator', 'Simulation').isNsfw,
      isTrue,
    ); // conservative
  });
}
