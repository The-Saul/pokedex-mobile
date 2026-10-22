import '../models/pokemon.dart';

/// Calculates damage multipliers from the standard Pokémon type chart.
class TypeEffectiveness {
  const TypeEffectiveness._();

  static const Map<String, Set<String>> _superEffective = {
    'normal': {},
    'fire': {'grass', 'ice', 'bug', 'steel'},
    'water': {'fire', 'ground', 'rock'},
    'electric': {'water', 'flying'},
    'grass': {'water', 'ground', 'rock'},
    'ice': {'grass', 'ground', 'flying', 'dragon'},
    'fighting': {'normal', 'ice', 'rock', 'dark', 'steel'},
    'poison': {'grass', 'fairy'},
    'ground': {'fire', 'electric', 'poison', 'rock', 'steel'},
    'flying': {'grass', 'fighting', 'bug'},
    'psychic': {'fighting', 'poison'},
    'bug': {'grass', 'psychic', 'dark'},
    'rock': {'fire', 'ice', 'flying', 'bug'},
    'ghost': {'psychic', 'ghost'},
    'dragon': {'dragon'},
    'dark': {'psychic', 'ghost'},
    'steel': {'ice', 'rock', 'fairy'},
    'fairy': {'fighting', 'dragon', 'dark'},
  };

  static const Map<String, Set<String>> _notVeryEffective = {
    'normal': {'rock', 'steel'},
    'fire': {'fire', 'water', 'rock', 'dragon'},
    'water': {'water', 'grass', 'dragon'},
    'electric': {'electric', 'grass', 'dragon'},
    'grass': {'fire', 'grass', 'poison', 'flying', 'bug', 'dragon', 'steel'},
    'ice': {'fire', 'water', 'ice', 'steel'},
    'fighting': {'poison', 'flying', 'psychic', 'bug', 'fairy'},
    'poison': {'poison', 'ground', 'rock', 'ghost'},
    'ground': {'grass', 'bug'},
    'flying': {'electric', 'rock', 'steel'},
    'psychic': {'psychic', 'steel'},
    'bug': {'fire', 'fighting', 'poison', 'flying', 'ghost', 'steel', 'fairy'},
    'rock': {'fighting', 'ground', 'steel'},
    'ghost': {'dark'},
    'dragon': {'steel'},
    'dark': {'fighting', 'dark', 'fairy'},
    'steel': {'fire', 'water', 'electric', 'steel'},
    'fairy': {'fire', 'poison', 'steel'},
  };

  static const Map<String, Set<String>> _noEffect = {
    'normal': {'ghost'},
    'electric': {'ground'},
    'fighting': {'ghost'},
    'poison': {'steel'},
    'ground': {'flying'},
    'psychic': {'dark'},
    'ghost': {'normal'},
    'dragon': {'fairy'},
  };

  static double against(String attackType, List<String> defendingTypes) {
    final attack = attackType.toLowerCase();
    var multiplier = 1.0;
    for (final type in defendingTypes.map((value) => value.toLowerCase())) {
      if (_noEffect[attack]?.contains(type) ?? false) return 0;
      if (_superEffective[attack]?.contains(type) ?? false) {
        multiplier *= 2;
      } else if (_notVeryEffective[attack]?.contains(type) ?? false) {
        multiplier *= 0.5;
      }
    }
    return multiplier;
  }

  static List<TypeMatchup> forPokemon(Pokemon attacker, Pokemon defender) =>
      attacker.types
          .map(
            (type) => TypeMatchup(
              type: type,
              multiplier: against(type, defender.types),
            ),
          )
          .toList()
        ..sort((a, b) => b.multiplier.compareTo(a.multiplier));
}

class TypeMatchup {
  const TypeMatchup({required this.type, required this.multiplier});

  final String type;
  final double multiplier;
}
