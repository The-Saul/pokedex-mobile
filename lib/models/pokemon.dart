class Pokemon {
  const Pokemon({
    required this.id,
    required this.name,
    required this.types,
    this.stats = const {},
    this.abilities = const [],
  });

  final int id;
  final String name;
  final List<String> types;
  final Map<String, int> stats;
  final List<PokemonAbility> abilities;

  String get imageUrl =>
      'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/$id.png';

  factory Pokemon.fromJson(Map<String, dynamic> json) {
    final types = (json['types'] as List<dynamic>? ?? const [])
        .map((item) => item['type']['name'] as String)
        .toList();
    final stats = {
      for (final item in json['stats'] as List<dynamic>? ?? const [])
        item['stat']['name'] as String: item['base_stat'] as int,
    };
    final abilities = (json['abilities'] as List<dynamic>? ?? const []).map((
      item,
    ) {
      final ability = item['ability'] as Map<String, dynamic>;
      return PokemonAbility(
        name: ability['name'] as String,
        isHidden: item['is_hidden'] as bool? ?? false,
      );
    }).toList();

    return Pokemon(
      id: json['id'] as int,
      name: json['name'] as String,
      types: types,
      stats: stats,
      abilities: abilities,
    );
  }
}

class PokemonAbility {
  const PokemonAbility({required this.name, this.isHidden = false});

  final String name;
  final bool isHidden;

  factory PokemonAbility.fromJson(Map<String, dynamic> json) => PokemonAbility(
    name: json['name'] as String,
    isHidden: json['is_hidden'] as bool? ?? false,
  );

  Map<String, Object?> toJson() => {'name': name, 'is_hidden': isHidden};
}
