import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'data/pokedex_database.dart';
import 'models/pokemon.dart';

export 'models/pokemon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await PokedexDatabase.open();
  runApp(PokedexApp(database: database));
}

class PokedexApp extends StatelessWidget {
  const PokedexApp({super.key, required this.database});

  final PokedexDatabase database;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokédex de Bolso',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFF9EF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE94B4B),
          surface: const Color(0xFFFFF9EF),
        ),
        fontFamily: 'Roboto',
      ),
      home: PokedexHomePage(database: database),
    );
  }
}

abstract interface class PokemonRepository {
  Future<List<Pokemon>> getPage({required int offset, int limit = 20});
  Future<Pokemon> search(String query);
}

class PokeApiService implements PokemonRepository {
  PokeApiService({this.database});

  static const _baseUrl = 'https://pokeapi.co/api/v2';
  final PokedexDatabase? database;
  final Map<String, Pokemon> _cache = {};

  @override
  Future<List<Pokemon>> getPage({required int offset, int limit = 20}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/pokemon?limit=$limit&offset=$offset'),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Não foi possível carregar a Pokédex.');
    }

    final results = jsonDecode(response.body)['results'] as List<dynamic>;
    return Future.wait(
      results.map((item) => _getPokemon(item['name'] as String)),
    );
  }

  @override
  Future<Pokemon> search(String query) =>
      _getPokemon(query.toLowerCase().trim());

  Future<Pokemon> _getPokemon(String name) async {
    if (_cache.containsKey(name)) return _cache[name]!;

    final response = await http.get(Uri.parse('$_baseUrl/pokemon/$name'));
    if (response.statusCode == 404) {
      throw const FormatException(
        'Pokémon não encontrado. Confira o nome ou número.',
      );
    }
    if (response.statusCode != 200) {
      throw const FormatException('Não foi possível carregar este Pokémon.');
    }

    final pokemon = Pokemon.fromJson(jsonDecode(response.body));
    _cache[pokemon.name] = pokemon;
    await database?.savePokemon(pokemon);
    return pokemon;
  }
}

class PokedexHomePage extends StatefulWidget {
  const PokedexHomePage({super.key, this.repository, this.database});

  final PokemonRepository? repository;
  final PokedexDatabase? database;

  @override
  State<PokedexHomePage> createState() => _PokedexHomePageState();
}

class _PokedexHomePageState extends State<PokedexHomePage> {
  late final PokemonRepository _api;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final List<Pokemon> _pokemon = [];
  final Set<int> _favorites = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isSearchMode = false;
  bool _hasMore = true;
  String? _error;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _api = widget.repository ?? PokeApiService(database: widget.database);
    _loadFavorites();
    _loadPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final database = widget.database;
    if (database == null) return;
    final favoriteIds = await database.getFavoriteIds();
    if (!mounted) return;
    setState(() => _favorites.addAll(favoriteIds));
  }

  void _onScroll() {
    if (_isSearchMode ||
        !_hasMore ||
        _isLoading ||
        _isLoadingMore ||
        _error != null) {
      return;
    }
    if (_scrollController.position.extentAfter < 360) {
      _loadPage(loadMore: true);
    }
  }

  Future<void> _loadPage({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final page = await _api.getPage(offset: loadMore ? _offset : 0);
      if (!mounted) return;
      setState(() {
        if (!loadMore) _pokemon.clear();
        _pokemon.addAll(page);
        _offset = (loadMore ? _offset : 0) + page.length;
        _hasMore = page.length == 20;
        _isLoading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sem conexão no momento. Tente novamente.';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _isSearchMode = true;
    });
    try {
      final result = await _api.search(query);
      if (!mounted) return;
      setState(() {
        _pokemon
          ..clear()
          ..add(result);
        _isLoading = false;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _pokemon.clear();
        _error = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Sem conexão no momento. Tente novamente.';
        _isLoading = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
      _hasMore = true;
      _error = null;
      _offset = 0;
    });
    _loadPage();
  }

  Future<void> _toggleFavorite(Pokemon pokemon) async {
    final database = widget.database;
    if (database != null) {
      await database.toggleFavorite(pokemon);
      final favoriteIds = await database.getFavoriteIds();
      if (!mounted) return;
      setState(() {
        _favorites
          ..clear()
          ..addAll(favoriteIds);
      });
      return;
    }
    setState(() {
      if (!_favorites.add(pokemon.id)) _favorites.remove(pokemon.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildSearchField()),
            SliverToBoxAdapter(child: _buildHero()),
            SliverToBoxAdapter(child: _buildSectionTitle()),
            if (_isLoading && _pokemon.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null && _pokemon.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _buildError())
            else if (_pokemon.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Nenhum Pokémon encontrado.')),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                sliver: SliverGrid.builder(
                  itemCount: _pokemon.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final pokemon = _pokemon[index];
                    return PokemonCard(
                      pokemon: pokemon,
                      isFavorite: _favorites.contains(pokemon.id),
                      onFavoriteTap: () => _toggleFavorite(pokemon),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PokemonDetailsPage(pokemon: pokemon),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE94B4B),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33E94B4B),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.catching_pokemon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POKÉDEX',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE94B4B),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'de bolso',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF292D35),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              tooltip: 'Atualizar lista',
              onPressed: _isLoading ? null : () => _loadPage(),
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF555D68)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 168,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(
            colors: [Color(0xFFEF5A4F), Color(0xFFE63D55)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33E94B4B),
              blurRadius: 18,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -16,
              bottom: -42,
              child: Icon(
                Icons.catching_pokemon,
                size: 190,
                color: Colors.white.withValues(alpha: 0.13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 21, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'SUA AVENTURA COMEÇA AQUI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Encontre seu\npróximo parceiro!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      height: 1.12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Explore o mundo Pokémon',
                    style: TextStyle(
                      color: Color(0xFFFFE9DE),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: 'Buscar por nome ou número',
          hintStyle: const TextStyle(color: Color(0xFFA5AAB1), fontSize: 13),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFFE94B4B),
          ),
          suffixIcon: IconButton(
            tooltip: 'Buscar Pokémon',
            onPressed: _search,
            icon: const Icon(
              Icons.arrow_forward_rounded,
              color: Color(0xFFE94B4B),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE94B4B), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 25, 20, 14),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pokémon',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF292D35),
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Toque em um card para favoritar',
                  style: TextStyle(fontSize: 12, color: Color(0xFF858B94)),
                ),
              ],
            ),
          ),
          if (_isSearchMode)
            TextButton.icon(
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('Limpar'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE94B4B),
              ),
            )
          else
            Text(
              '${_favorites.length} ♡',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE94B4B),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 42,
              color: Color(0xFFADB2B9),
            ),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Algo deu errado.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF666D77)),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSearchMode ? _search : () => _loadPage(),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  void _openComparator() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PokemonComparePage(repository: _api, database: widget.database),
      ),
    );
  }

  void _openQuiz() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PokemonQuizPage(repository: _api, database: widget.database),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: _NavItem(
                  icon: Icons.grid_view_rounded,
                  label: 'Pokédex',
                  selected: true,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.compare_arrows_rounded,
                  label: 'Comparar',
                  onTap: _openComparator,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.help_outline_rounded,
                  label: 'Quiz',
                  onTap: _openQuiz,
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.favorite_rounded,
                  label: 'Meu time',
                  badge: _favorites.isEmpty ? null : '${_favorites.length}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PokemonQuizPage extends StatefulWidget {
  PokemonQuizPage({
    super.key,
    required this.repository,
    required this.database,
    Random? random,
  }) : random = random ?? Random();

  final PokemonRepository repository;
  final PokedexDatabase? database;
  final Random random;

  @override
  State<PokemonQuizPage> createState() => _PokemonQuizPageState();
}

class _PokemonQuizPageState extends State<PokemonQuizPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confettiController;
  Pokemon? _answer;
  List<Pokemon> _choices = [];
  String? _selectedName;
  List<QuizAttempt> _history = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  int get _correctAnswers =>
      _history.where((attempt) => attempt.isCorrect).length;

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    );
    _loadHistory();
    _loadRound();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await widget.database?.getQuizHistory() ?? const [];
    if (mounted) setState(() => _history = history);
  }

  Future<void> _loadRound() async {
    setState(() {
      _isLoading = true;
      _selectedName = null;
      _error = null;
    });
    try {
      final answerId = widget.random.nextInt(151) + 1;
      final ids = <int>{answerId};
      while (ids.length < 4) {
        ids.add(widget.random.nextInt(151) + 1);
      }
      final pokemon = await Future.wait(
        ids.map((id) => widget.repository.search('$id')),
      );
      pokemon.shuffle(widget.random);
      if (!mounted) return;
      setState(() {
        _answer = pokemon.firstWhere((item) => item.id == answerId);
        _choices = pokemon;
        _isLoading = false;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar o desafio. Confira sua conexão.';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitGuess(Pokemon choice) async {
    final answer = _answer;
    if (answer == null || _selectedName != null || _isSaving) return;
    setState(() {
      _selectedName = choice.name;
      _isSaving = true;
    });
    if (choice.id == answer.id) {
      _confettiController.forward(from: 0);
    }
    try {
      await widget.database?.saveQuizAttempt(
        answer: answer,
        guess: choice.name,
      );
      await _loadHistory();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Resposta conferida, mas não foi possível salvá-la no SQLite.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final answer = _answer;
    final answered = _selectedName != null;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9EF),
      appBar: AppBar(
        title: const Text(
          'Quem é esse Pokémon?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFF9EF),
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF315FA8), Color(0xFF4787D4)],
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.quiz_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adivinhe pela silhueta',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Acertos: $_correctAnswers de ${_history.length}',
                              style: const TextStyle(
                                color: Color(0xFFDDEBFF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Center(
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : _error != null && answer == null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.wifi_off_rounded,
                                color: Color(0xFF858B94),
                                size: 38,
                              ),
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton(
                                onPressed: _loadRound,
                                child: const Text('Tentar novamente'),
                              ),
                            ],
                          )
                        : answer == null
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ColorFiltered(
                                colorFilter: answered
                                    ? const ColorFilter.mode(
                                        Colors.transparent,
                                        BlendMode.dst,
                                      )
                                    : const ColorFilter.mode(
                                        Colors.black,
                                        BlendMode.srcIn,
                                      ),
                                child: Image.network(
                                  answer.imageUrl,
                                  height: 190,
                                  width: 190,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.catching_pokemon,
                                    size: 150,
                                    color: Color(0xFFE94B4B),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                answered
                                    ? _capitalize(answer.name)
                                    : 'Quem é esse Pokémon?',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF292D35),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 18),
                for (final choice in _choices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OutlinedButton(
                      onPressed: answered || _isLoading
                          ? null
                          : () => _submitGuess(choice),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        alignment: Alignment.centerLeft,
                        backgroundColor: answered && choice.name == answer?.name
                            ? const Color(0xFFE2F4E8)
                            : answered && choice.name == _selectedName
                            ? const Color(0xFFFFE5E1)
                            : Colors.white,
                        side: BorderSide(
                          color: answered && choice.name == answer?.name
                              ? const Color(0xFF49A96B)
                              : const Color(0xFFE8E8E8),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _capitalize(choice.name),
                              style: const TextStyle(
                                color: Color(0xFF292D35),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (answered && choice.name == answer?.name)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF49A96B),
                            ),
                          if (answered &&
                              choice.name == _selectedName &&
                              choice.name != answer?.name)
                            const Icon(
                              Icons.cancel_rounded,
                              color: Color(0xFFE94B4B),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (answered) ...[
                  const SizedBox(height: 4),
                  Text(
                    _selectedName == answer?.name
                        ? 'Isso aí! Resposta correta!'
                        : 'Quase! A resposta era ${_capitalize(answer!.name)}.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _selectedName == answer?.name
                          ? const Color(0xFF368B55)
                          : const Color(0xFFE94B4B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _loadRound,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Próximo Pokémon'),
                  ),
                ],
                if (_error != null && answer != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE94B4B)),
                  ),
                ],
                if (_history.isNotEmpty) ...[
                  const SizedBox(height: 25),
                  const Text(
                    'Últimas tentativas',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF292D35),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final attempt in _history.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        attempt.isCorrect
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: attempt.isCorrect
                            ? const Color(0xFF49A96B)
                            : const Color(0xFFE94B4B),
                      ),
                      title: Text(
                        _capitalize(attempt.pokemon.name),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Sua resposta: ${_capitalize(attempt.guess)}',
                      ),
                      trailing: Text(
                        attempt.isCorrect ? 'Acerto' : 'Erro',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(animation: _confettiController),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.animation}) : super(repaint: animation) {
    final random = Random(23);
    _particles = List.generate(90, (_) {
      return _ConfettiParticle(
        horizontalVelocity: (random.nextDouble() - 0.5) * 2.2,
        verticalVelocity: random.nextDouble() * 1.2 + 0.25,
        size: random.nextDouble() * 5 + 3,
        delay: random.nextDouble() * 0.35,
        color: _colors[random.nextInt(_colors.length)],
        isCircle: random.nextBool(),
        rotation: random.nextDouble() * pi,
      );
    });
  }

  final Animation<double> animation;
  late final List<_ConfettiParticle> _particles;

  static const _colors = [
    Color(0xFFE94B4B),
    Color(0xFFFFC857),
    Color(0xFF48BFA3),
    Color(0xFF6C63C7),
    Color(0xFF4D96FF),
    Color(0xFFFF85A1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    if (progress <= 0 || progress >= 1) return;

    for (final particle in _particles) {
      final elapsed = (progress - particle.delay).clamp(0.0, 1.0);
      if (elapsed == 0) continue;
      final fade = ((1 - progress) * 1.8).clamp(0.0, 1.0);
      final paint = Paint()..color = particle.color.withValues(alpha: fade);
      final x =
          size.width * 0.5 +
          particle.horizontalVelocity * elapsed * size.width * 0.55;
      final y =
          size.height * 0.24 +
          particle.verticalVelocity * elapsed * size.height * 0.8 +
          elapsed * elapsed * size.height * 0.35;
      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: particle.size,
        height: particle.size * 1.5,
      );

      if (particle.isCircle) {
        canvas.drawCircle(rect.center, particle.size * 0.55, paint);
      } else {
        canvas.save();
        canvas.translate(rect.center.dx, rect.center.dy);
        canvas.rotate(particle.rotation + elapsed * 8);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: rect.width,
            height: rect.height,
          ),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => false;
}

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.horizontalVelocity,
    required this.verticalVelocity,
    required this.size,
    required this.delay,
    required this.color,
    required this.isCircle,
    required this.rotation,
  });

  final double horizontalVelocity;
  final double verticalVelocity;
  final double size;
  final double delay;
  final Color color;
  final bool isCircle;
  final double rotation;
}

class PokemonCard extends StatelessWidget {
  const PokemonCard({
    super.key,
    required this.pokemon,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onTap,
  });

  final Pokemon pokemon;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onTap;

  static const _typeColors = <String, Color>{
    'grass': Color(0xFF64BC76),
    'fire': Color(0xFFF18A55),
    'water': Color(0xFF63A6E8),
    'bug': Color(0xFF9AB84B),
    'normal': Color(0xFFA6A5A0),
    'poison': Color(0xFFA76BC1),
    'electric': Color(0xFFE8BD42),
    'ground': Color(0xFFC69B65),
    'fairy': Color(0xFFE58EB2),
    'fighting': Color(0xFFD76B61),
    'psychic': Color(0xFFE87892),
    'rock': Color(0xFFA99A67),
    'ghost': Color(0xFF7774AE),
    'ice': Color(0xFF73C7C5),
    'dragon': Color(0xFF7765CE),
    'dark': Color(0xFF74665E),
    'steel': Color(0xFF8B9BA8),
    'flying': Color(0xFF8D9FE0),
  };

  Color get _color =>
      _typeColors[pokemon.types.firstOrNull] ?? const Color(0xFF63A6E8);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D202B3C),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned(
                right: -24,
                top: 35,
                child: Icon(
                  Icons.catching_pokemon,
                  size: 132,
                  color: _color.withValues(alpha: 0.09),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(7, 8, 7, 0),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              color: _color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Image.network(
                            pokemon.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.catching_pokemon,
                              size: 78,
                              color: _color,
                            ),
                            loadingBuilder: (context, child, progress) =>
                                progress == null
                                ? child
                                : SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _color,
                                    ),
                                  ),
                          ),
                          Positioned(
                            top: 3,
                            right: 1,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: onFavoriteTap,
                              tooltip: isFavorite
                                  ? 'Remover dos favoritos'
                                  : 'Adicionar aos favoritos',
                              icon: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: isFavorite
                                    ? const Color(0xFFE94B4B)
                                    : const Color(0xFFB5BAC1),
                                size: 21,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${pokemon.id.toString().padLeft(3, '0')}',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: _color,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _capitalize(pokemon.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF292D35),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: pokemon.types
                              .take(2)
                              .map(
                                (type) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (_typeColors[type] ?? _color)
                                        .withValues(alpha: 0.13),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _capitalize(type),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: _typeColors[type] ?? _color,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PokemonComparePage extends StatefulWidget {
  const PokemonComparePage({
    super.key,
    required this.repository,
    required this.database,
  });

  final PokemonRepository repository;
  final PokedexDatabase? database;

  @override
  State<PokemonComparePage> createState() => _PokemonComparePageState();
}

class _PokemonComparePageState extends State<PokemonComparePage> {
  final _firstController = TextEditingController();
  final _secondController = TextEditingController();
  Pokemon? _first;
  Pokemon? _second;
  int? _loadingSlot;
  int _savedComparisons = 0;
  String? _error;
  bool _isSaving = false;
  bool _comparisonSaved = false;

  @override
  void initState() {
    super.initState();
    _loadComparisonCount();
  }

  @override
  void dispose() {
    _firstController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  Future<void> _loadComparisonCount() async {
    final count = await widget.database?.getComparisonCount() ?? 0;
    if (mounted) setState(() => _savedComparisons = count);
  }

  Future<void> _loadPokemon(int slot) async {
    final controller = slot == 1 ? _firstController : _secondController;
    final query = controller.text.trim();
    if (query.isEmpty) {
      setState(() => _error = 'Digite um nome ou número de Pokémon.');
      return;
    }

    setState(() {
      _loadingSlot = slot;
      _error = null;
      _comparisonSaved = false;
    });
    try {
      final pokemon = await widget.repository.search(query);
      if (!mounted) return;
      setState(() {
        if (slot == 1) {
          _first = pokemon;
        } else {
          _second = pokemon;
        }
        _loadingSlot = null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loadingSlot = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível buscar o Pokémon. Tente novamente.';
        _loadingSlot = null;
      });
    }
  }

  Future<void> _saveComparison() async {
    final first = _first;
    final second = _second;
    if (first == null || second == null) return;
    if (first.id == second.id) {
      setState(() => _error = 'Escolha dois Pokémon diferentes para comparar.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await widget.database?.saveComparison(first, second);
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _comparisonSaved = true;
        _savedComparisons++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Não foi possível salvar a comparação no SQLite.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9EF),
      appBar: AppBar(
        title: const Text(
          'Comparador',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFF9EF),
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7166C8), Color(0xFF9B6CCB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.compare_arrows_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Quem leva a melhor?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Escolha dois Pokémon e compare os atributos base.',
                    style: TextStyle(color: Color(0xFFEDE8FF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildPokemonPicker(
              slot: 1,
              controller: _firstController,
              pokemon: _first,
              label: 'Primeiro Pokémon',
              hint: 'Ex.: pikachu ou 25',
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'VS',
                style: TextStyle(
                  color: Color(0xFFE94B4B),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildPokemonPicker(
              slot: 2,
              controller: _secondController,
              pokemon: _second,
              label: 'Segundo Pokémon',
              hint: 'Ex.: charizard ou 6',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFC53F3F),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_first != null && _second != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _isSaving ? null : _saveComparison,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.equalizer_rounded),
                label: Text(_isSaving ? 'Salvando...' : 'Comparar e salvar'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE94B4B),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 18),
              _buildComparisonResults(),
              if (_comparisonSaved) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: Color(0xFF53A875),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Salva no SQLite • $_savedComparisons comparações',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF568165),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPokemonPicker({
    required int slot,
    required TextEditingController controller,
    required Pokemon? pokemon,
    required String label,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D202B3C),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF858B94),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _loadPokemon(slot),
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(13),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Buscar $label',
                onPressed: _loadingSlot == slot
                    ? null
                    : () => _loadPokemon(slot),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFE94B4B),
                ),
                icon: _loadingSlot == slot
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ],
          ),
          if (pokemon != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Image.network(
                  pokemon.imageUrl,
                  width: 54,
                  height: 54,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.catching_pokemon,
                    size: 42,
                    color: Color(0xFFE94B4B),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${pokemon.id.toString().padLeft(3, '0')}  ${_capitalize(pokemon.name)}',
                        style: const TextStyle(
                          color: Color(0xFF292D35),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pokemon.types.map(_capitalize).join(' • '),
                        style: const TextStyle(
                          color: Color(0xFF858B94),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComparisonResults() {
    final first = _first!;
    final second = _second!;
    const stats = [('HP', 'hp'), ('Ataque', 'attack'), ('Defesa', 'defense')];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D202B3C),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ATRIBUTOS BASE',
            style: TextStyle(
              color: Color(0xFF858B94),
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 15),
          for (final (label, key) in stats) ...[
            _ComparisonStatRow(
              label: label,
              firstValue: first.stats[key] ?? 0,
              secondValue: second.stats[key] ?? 0,
            ),
            if (key != 'defense') const Divider(height: 22),
          ],
        ],
      ),
    );
  }
}

class _ComparisonStatRow extends StatelessWidget {
  const _ComparisonStatRow({
    required this.label,
    required this.firstValue,
    required this.secondValue,
  });

  final String label;
  final int firstValue;
  final int secondValue;

  @override
  Widget build(BuildContext context) {
    const winner = Color(0xFF53A875);
    const neutral = Color(0xFF292D35);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$firstValue',
            textAlign: TextAlign.left,
            style: TextStyle(
              color: firstValue > secondValue ? winner : neutral,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF737A84),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            '$secondValue',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: secondValue > firstValue ? winner : neutral,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class PokemonDetailsPage extends StatelessWidget {
  const PokemonDetailsPage({super.key, required this.pokemon});

  final Pokemon pokemon;

  @override
  Widget build(BuildContext context) {
    final color =
        PokemonCard._typeColors[pokemon.types.firstOrNull] ??
        const Color(0xFF63A6E8);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9EF),
      appBar: AppBar(
        title: const Text(
          'Detalhes',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFFFF9EF),
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PokemonArtworkHeader(pokemon: pokemon, color: color),
            const SizedBox(height: 22),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Atributos base',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF292D35),
                    ),
                  ),
                ),
                Text(
                  'STATS',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D202B3C),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _StatBar(
                    label: 'HP',
                    value: pokemon.stats['hp'] ?? 0,
                    color: const Color(0xFFE87575),
                  ),
                  const SizedBox(height: 18),
                  _StatBar(
                    label: 'Ataque',
                    value: pokemon.stats['attack'] ?? 0,
                    color: const Color(0xFFF1A553),
                  ),
                  const SizedBox(height: 18),
                  _StatBar(
                    label: 'Defesa',
                    value: pokemon.stats['defense'] ?? 0,
                    color: const Color(0xFF63A6E8),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E8),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFE7775E)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Os atributos exibem os valores base deste Pokémon.',
                      style: TextStyle(
                        color: Color(0xFF725A51),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PokemonArtworkHeader extends StatelessWidget {
  const _PokemonArtworkHeader({required this.pokemon, required this.color});

  final Pokemon pokemon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -12,
            bottom: -40,
            child: Icon(
              Icons.catching_pokemon,
              size: 210,
              color: Colors.white.withValues(alpha: 0.13),
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Text(
              '#${pokemon.id.toString().padLeft(3, '0')}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 16,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 22,
            ),
          ),
          Positioned(
            top: 32,
            child: Image.network(
              pokemon.imageUrl,
              width: 190,
              height: 190,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.catching_pokemon,
                size: 150,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Text(
                  _capitalize(pokemon.name),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  children: pokemon.types
                      .map(
                        (type) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.23),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _capitalize(type),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF626A75),
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: (value / 255).clamp(0.0, 1.0),
                  minHeight: 9,
                  backgroundColor: const Color(0xFFF1F2F4),
                  color: color,
                ),
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '$value',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF292D35),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFE94B4B) : const Color(0xFFA4A9B1);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: color),
                if (badge != null)
                  Positioned(
                    right: -9,
                    top: -7,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE94B4B),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          fontSize: 8,
                          height: 1,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
