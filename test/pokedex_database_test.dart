import 'package:flutter_test/flutter_test.dart';
import 'package:pokedex_mobile/data/pokedex_database.dart';
import 'package:pokedex_mobile/models/pokemon.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late PokedexDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = await PokedexDatabase.openForTesting(databaseFactoryFfi);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists favorites and toggles them off', () async {
    final pikachu = _pokemon(25, 'pikachu');

    await database.toggleFavorite(pikachu);
    expect(await database.getFavoriteIds(), {25});
    expect((await database.getFavorites()).single.name, 'pikachu');

    await database.toggleFavorite(pikachu);
    expect(await database.getFavoriteIds(), isEmpty);
  });

  test(
    'stores a team of six, rejects a seventh, and compacts after removal',
    () async {
      for (var id = 1; id <= 6; id++) {
        await database.addToTeam(_pokemon(id, 'pokemon$id'));
      }

      await expectLater(
        database.addToTeam(_pokemon(7, 'pokemon7')),
        throwsA(isA<TeamLimitException>()),
      );
      expect((await database.getTeam()).map((pokemon) => pokemon.id), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);

      await database.removeFromTeam(3);
      await database.addToTeam(_pokemon(7, 'pokemon7'));
      expect((await database.getTeam()).map((pokemon) => pokemon.id), [
        1,
        2,
        4,
        5,
        6,
        7,
      ]);
    },
  );

  test('stores correct and incorrect minigame attempts', () async {
    final pikachu = _pokemon(25, 'pikachu');

    await database.saveQuizAttempt(answer: pikachu, guess: 'Pikachu');
    await database.saveQuizAttempt(answer: pikachu, guess: 'Raichu');
    final history = await database.getQuizHistory();

    expect(history, hasLength(2));
    expect(history.first.isCorrect, isFalse);
    expect(history.last.isCorrect, isTrue);
    expect(history.last.pokemon.name, 'pikachu');
  });

  test('saves comparison snapshots in SQLite', () async {
    await database.saveComparison(
      _pokemon(1, 'bulbasaur'),
      _pokemon(6, 'charizard'),
    );

    expect(await database.getComparisonCount(), 1);
  });
}

Pokemon _pokemon(int id, String name) => Pokemon(
  id: id,
  name: name,
  types: const ['normal'],
  stats: const {'hp': 50, 'attack': 60, 'defense': 70},
);
