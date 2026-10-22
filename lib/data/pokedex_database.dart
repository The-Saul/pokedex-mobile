import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../models/pokemon.dart';

class PokedexDatabase {
  PokedexDatabase._(this._database);

  static const databaseName = 'pokedex_de_bolso.db';
  static PokedexDatabase? _instance;

  final Database _database;

  static Future<PokedexDatabase> open() async {
    if (_instance != null) return _instance!;

    if (kIsWeb) {
      // The web implementation stores the SQLite file in browser IndexedDB.
      databaseFactory = databaseFactoryFfiWeb;
    }

    final databasePath = kIsWeb
        ? databaseName
        : path.join(await getDatabasesPath(), databaseName);
    final database = await openDatabase(
      databasePath,
      version: 2,
      onConfigure: _configure,
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return _instance = PokedexDatabase._(database);
  }

  /// Opens an isolated in-memory SQLite database for tests.
  static Future<PokedexDatabase> openForTesting(DatabaseFactory factory) async {
    final database = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: _configure,
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    return PokedexDatabase._(database);
  }

  static Future<void> _configure(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await database.execute(
        "ALTER TABLE pokemon ADD COLUMN abilities_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE pokemon (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        types_json TEXT NOT NULL,
        stats_json TEXT NOT NULL,
        abilities_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE favorites (
        pokemon_id INTEGER PRIMARY KEY REFERENCES pokemon(id) ON DELETE CASCADE,
        added_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE team_members (
        pokemon_id INTEGER PRIMARY KEY REFERENCES pokemon(id) ON DELETE CASCADE,
        position INTEGER NOT NULL UNIQUE CHECK(position BETWEEN 1 AND 6),
        added_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE quiz_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pokemon_id INTEGER NOT NULL REFERENCES pokemon(id),
        guess TEXT NOT NULL,
        is_correct INTEGER NOT NULL,
        played_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE comparisons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_pokemon_id INTEGER NOT NULL REFERENCES pokemon(id),
        second_pokemon_id INTEGER NOT NULL REFERENCES pokemon(id),
        first_stats_json TEXT NOT NULL,
        second_stats_json TEXT NOT NULL,
        compared_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> savePokemon(Pokemon pokemon) async {
    await _upsertPokemon(_database, pokemon);
  }

  Future<Set<int>> getFavoriteIds() async {
    final rows = await _database.query('favorites', columns: ['pokemon_id']);
    return rows.map((row) => row['pokemon_id'] as int).toSet();
  }

  Future<List<Pokemon>> getFavorites() async {
    final rows = await _database.rawQuery('''
      SELECT p.* FROM favorites f
      JOIN pokemon p ON p.id = f.pokemon_id
      ORDER BY f.added_at DESC
    ''');
    return rows.map(_pokemonFromRow).toList();
  }

  Future<void> toggleFavorite(Pokemon pokemon) async {
    await _database.transaction((transaction) async {
      await _upsertPokemon(transaction, pokemon);
      final rows = await transaction.query(
        'favorites',
        columns: ['pokemon_id'],
        where: 'pokemon_id = ?',
        whereArgs: [pokemon.id],
      );
      if (rows.isEmpty) {
        await transaction.insert('favorites', {
          'pokemon_id': pokemon.id,
          'added_at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await transaction.delete(
          'favorites',
          where: 'pokemon_id = ?',
          whereArgs: [pokemon.id],
        );
      }
    });
  }

  Future<List<Pokemon>> getTeam() async {
    final rows = await _database.rawQuery('''
      SELECT p.* FROM team_members t
      JOIN pokemon p ON p.id = t.pokemon_id
      ORDER BY t.position ASC
    ''');
    return rows.map(_pokemonFromRow).toList();
  }

  Future<void> addToTeam(Pokemon pokemon) async {
    await _database.transaction((transaction) async {
      await _upsertPokemon(transaction, pokemon);
      final existing = await transaction.query(
        'team_members',
        columns: ['pokemon_id'],
        where: 'pokemon_id = ?',
        whereArgs: [pokemon.id],
      );
      if (existing.isNotEmpty) return;

      final members = await transaction.query('team_members');
      if (members.length >= 6) throw const TeamLimitException();
      await transaction.insert('team_members', {
        'pokemon_id': pokemon.id,
        'position': members.length + 1,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> removeFromTeam(int pokemonId) async {
    await _database.transaction((transaction) async {
      await transaction.delete(
        'team_members',
        where: 'pokemon_id = ?',
        whereArgs: [pokemonId],
      );
      final members = await transaction.query(
        'team_members',
        columns: ['pokemon_id'],
        orderBy: 'position ASC',
      );
      for (var index = 0; index < members.length; index++) {
        await transaction.update(
          'team_members',
          {'position': index + 1},
          where: 'pokemon_id = ?',
          whereArgs: [members[index]['pokemon_id']],
        );
      }
    });
  }

  Future<void> saveQuizAttempt({
    required Pokemon answer,
    required String guess,
  }) async {
    await _database.transaction((transaction) async {
      await _upsertPokemon(transaction, answer);
      await transaction.insert('quiz_attempts', {
        'pokemon_id': answer.id,
        'guess': guess.trim(),
        'is_correct': guess.trim().toLowerCase() == answer.name.toLowerCase()
            ? 1
            : 0,
        'played_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<List<QuizAttempt>> getQuizHistory({int limit = 50}) async {
    final rows = await _database.rawQuery(
      '''
      SELECT q.id AS attempt_id, q.guess, q.is_correct, q.played_at, p.*
      FROM quiz_attempts q JOIN pokemon p ON p.id = q.pokemon_id
      ORDER BY q.played_at DESC LIMIT ?
      ''',
      [limit],
    );
    return rows.map((row) => QuizAttempt.fromRow(row)).toList();
  }

  Future<void> saveComparison(Pokemon first, Pokemon second) async {
    await _database.transaction((transaction) async {
      await _upsertPokemon(transaction, first);
      await _upsertPokemon(transaction, second);
      await transaction.insert('comparisons', {
        'first_pokemon_id': first.id,
        'second_pokemon_id': second.id,
        'first_stats_json': jsonEncode(first.stats),
        'second_stats_json': jsonEncode(second.stats),
        'compared_at': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<int> getComparisonCount() async {
    final result = await _database.rawQuery(
      'SELECT COUNT(*) AS total FROM comparisons',
    );
    return result.single['total'] as int;
  }

  Future<void> close() => _database.close();

  static Future<void> _upsertPokemon(
    DatabaseExecutor executor,
    Pokemon pokemon,
  ) async {
    final values = _pokemonRow(pokemon);
    final id = values.remove('id') as int;
    await executor.insert('pokemon', {
      'id': id,
      ...values,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await executor.update('pokemon', values, where: 'id = ?', whereArgs: [id]);
  }

  static Map<String, Object?> _pokemonRow(Pokemon pokemon) => {
    'id': pokemon.id,
    'name': pokemon.name,
    'types_json': jsonEncode(pokemon.types),
    'stats_json': jsonEncode(pokemon.stats),
    'abilities_json': jsonEncode(
      pokemon.abilities.map((ability) => ability.toJson()).toList(),
    ),
    'updated_at': DateTime.now().millisecondsSinceEpoch,
  };

  static Pokemon _pokemonFromRow(Map<String, Object?> row) => Pokemon(
    id: row['id'] as int,
    name: row['name'] as String,
    types: (jsonDecode(row['types_json'] as String) as List<dynamic>)
        .cast<String>(),
    stats: (jsonDecode(row['stats_json'] as String) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, value as int)),
    abilities: (jsonDecode(row['abilities_json'] as String) as List<dynamic>)
        .map(
          (ability) => PokemonAbility.fromJson(
            Map<String, dynamic>.from(ability as Map),
          ),
        )
        .toList(),
  );
}

class QuizAttempt {
  const QuizAttempt({
    required this.id,
    required this.pokemon,
    required this.guess,
    required this.isCorrect,
    required this.playedAt,
  });

  final int id;
  final Pokemon pokemon;
  final String guess;
  final bool isCorrect;
  final DateTime playedAt;

  factory QuizAttempt.fromRow(Map<String, Object?> row) => QuizAttempt(
    id: row['attempt_id'] as int,
    pokemon: PokedexDatabase._pokemonFromRow(row),
    guess: row['guess'] as String,
    isCorrect: row['is_correct'] == 1,
    playedAt: DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int),
  );
}

class TeamLimitException implements Exception {
  const TeamLimitException();

  @override
  String toString() => 'O time pode ter no máximo seis Pokémon.';
}
