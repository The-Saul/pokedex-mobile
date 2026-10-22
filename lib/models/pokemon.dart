class Pokemon {
  const Pokemon({
    required this.id,
    required this.name,
    required this.types,
    this.stats = const {},
  });

  final int id;
  final String name;
  final List<String> types;
  final Map<String, int> stats;

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

    return Pokemon(
      id: json['id'] as int,
      name: json['name'] as String,
      types: types,
      stats: stats,
    );
  }
}
