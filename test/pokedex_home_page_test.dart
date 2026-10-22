import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokedex_mobile/main.dart';

class _FakePokemonRepository implements PokemonRepository {
  final searches = <String>[];

  @override
  Future<List<Pokemon>> getPage({required int offset, int limit = 20}) async {
    if (offset == 0) {
      return const [
        Pokemon(
          id: 1,
          name: 'bulbasaur',
          types: ['grass', 'poison'],
          stats: {'hp': 45, 'attack': 49, 'defense': 49},
        ),
        Pokemon(
          id: 4,
          name: 'charmander',
          types: ['fire'],
          stats: {'hp': 39, 'attack': 52, 'defense': 43},
        ),
      ];
    }
    return const [];
  }

  @override
  Future<Pokemon> search(String query) async {
    searches.add(query);
    return const Pokemon(id: 25, name: 'pikachu', types: ['electric']);
  }
}

void main() {
  testWidgets('shows the first Pokémon page and allows favoriting', (
    tester,
  ) async {
    final repository = _FakePokemonRepository();
    await tester.pumpWidget(
      MaterialApp(home: PokedexHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bulbasaur'), findsOneWidget);
    expect(find.text('Charmander'), findsOneWidget);
    expect(find.text('#001'), findsOneWidget);

    await tester.tap(find.byTooltip('Adicionar aos favoritos').first);
    await tester.pump();

    expect(find.text('1 ♡'), findsOneWidget);
    expect(find.byTooltip('Remover dos favoritos'), findsOneWidget);
  });

  testWidgets('searches by the submitted query', (tester) async {
    final repository = _FakePokemonRepository();
    await tester.pumpWidget(
      MaterialApp(home: PokedexHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'pikachu');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repository.searches, ['pikachu']);
    expect(find.text('Pikachu'), findsOneWidget);
    expect(find.text('Bulbasaur'), findsNothing);
  });

  testWidgets('opens Pokémon details with types and base stats', (
    tester,
  ) async {
    final repository = _FakePokemonRepository();
    await tester.pumpWidget(
      MaterialApp(home: PokedexHomePage(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Bulbasaur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bulbasaur'));
    await tester.pumpAndSettle();

    expect(find.text('Detalhes'), findsOneWidget);
    expect(find.text('#001'), findsOneWidget);
    expect(find.text('Grass'), findsOneWidget);
    expect(find.text('Poison'), findsOneWidget);
    expect(find.text('Atributos base'), findsOneWidget);
    expect(find.text('HP'), findsOneWidget);
    expect(find.text('Ataque'), findsOneWidget);
    expect(find.text('Defesa'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('49'), findsNWidgets(2));
  });
}
