import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading = false;
  bool _hasSearched = false;
  List<Game> _results = [];
  List<String> _history = [];
  int _searchToken = 0; // Ignores results of superseded searches

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _controller.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDesktopPlatform) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _history = prefs.getStringList('search_history') ?? []);
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', _history);
  }

  void _addToHistory(String query) {
    setState(() {
      _history.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
      _history.insert(0, query);
      if (_history.length > 10) _history.removeLast();
    });
    _saveHistory();
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _addToHistory(query);
    final token = ++_searchToken;
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });
    final results = await ScraperService().searchGames(query);
    if (!mounted || token != _searchToken) return;
    setState(() {
      _results = results;
      _isLoading = false;
    });
  }

  void _clear() {
    _controller.clear();
    _searchToken++;
    setState(() {
      _hasSearched = false;
      _isLoading = false;
      _results = [];
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ContentConstraint(
          maxWidth: 1400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(title: 'Search'),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.pagePadding,
                  8,
                  context.pagePadding,
                  16,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      decoration: InputDecoration(
                        hintText: 'Search for games…',
                        prefixIcon: const Icon(LucideIcons.search, size: 20),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: _clear,
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _hasSearched
                    ? _buildResults()
                    : _buildHistory(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.searchX, size: 48, color: Colors.white12),
            SizedBox(height: 12),
            Text(
              'No results found',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${_results.length} results',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            0,
            context.pagePadding,
            32,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 560,
              mainAxisExtent: 106,
              mainAxisSpacing: 10,
              crossAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => GameListTile(game: _results[i]),
              childCount: _results.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Text(
          'Search FitGirl Repacks by game title',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: context.pagePadding - 4),
      children: [
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Recent Searches',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                setState(() => _history.clear());
                _saveHistory();
              },
              child: const Text(
                'Clear all',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in _history)
              InputChip(
                avatar: const Icon(LucideIcons.history, size: 14),
                label: Text(q),
                backgroundColor: AppTheme.surfaceHighlight,
                side: const BorderSide(color: AppTheme.border),
                onPressed: () {
                  _controller.text = q;
                  _search(q);
                },
                onDeleted: () {
                  setState(() => _history.remove(q));
                  _saveHistory();
                },
              ),
          ],
        ),
      ],
    );
  }
}
