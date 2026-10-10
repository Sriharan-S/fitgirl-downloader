import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/router.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/favorites_service.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/services/torrent_engine.dart';
import 'package:fitgirl_mobile_flutter/widgets/torrent_metadata_dialog.dart';
import 'package:fitgirl_mobile_flutter/widgets/background_guide.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_option_tile.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_details_skeleton.dart';
import 'package:fitgirl_mobile_flutter/widgets/success_action_dialog.dart';
import 'package:fitgirl_mobile_flutter/services/cache_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class GameDetailsScreen extends ConsumerStatefulWidget {
  final String? gameId; // The game's page URL
  final Game? initialGame;

  const GameDetailsScreen({super.key, this.gameId, this.initialGame});

  @override
  ConsumerState<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends ConsumerState<GameDetailsScreen> {
  Game? _game;
  bool _isLoading = true;
  bool _isFavorite = false;
  bool _descriptionExpanded = false;

  String? get _url => widget.gameId ?? widget.initialGame?.url;

  /// Whether the bundled torrent engine is available on this device.
  bool _torrentInApp = false;

  @override
  void initState() {
    super.initState();
    _load();
    TorrentEngine().isAvailable.then((ok) {
      if (mounted) setState(() => _torrentInApp = ok);
    });
  }

  Future<void> _load() async {
    final url = _url;
    if (url == null || url.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    // Last known copy first (no skeleton), then refresh quietly.
    final cached = _game == null ? await CacheStore().readGame(url) : null;
    if (cached != null && mounted) {
      final isFav = await FavoritesService().isFavorite(cached.url);
      if (!mounted) return;
      setState(() {
        _game = cached;
        _isFavorite = isFav;
        _isLoading = false;
        _descriptionExpanded = context.isWide;
      });
      _warnIfAdult(cached);
    } else if (_game == null) {
      setState(() => _isLoading = true);
    }

    final fresh = await ScraperService().getGameDetails(url);
    if (!mounted) return;
    if (fresh == null) {
      // Offline: keep showing the cached copy if there is one.
      if (_game == null) setState(() => _isLoading = false);
      return;
    }
    final isFav = await FavoritesService().isFavorite(fresh.url);
    if (!mounted) return;
    final firstShow = _game == null;
    setState(() {
      _game = fresh;
      _isFavorite = isFav;
      _isLoading = false;
      if (firstShow) _descriptionExpanded = context.isWide;
    });
    if (firstShow) _warnIfAdult(fresh);
  }

  bool _warnedAdult = false;
  void _warnIfAdult(Game game) {
    if (_warnedAdult || !game.isNsfw) return;
    _warnedAdult = true;
    _showAdultContentWarning();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _toggleFavorite() async {
    final game = _game;
    if (game == null) return;
    final adding = !_isFavorite;
    setState(() => _isFavorite = adding);
    try {
      if (adding) {
        await FavoritesService().addFavorite(game);
        _snack('Added to Library');
      } else {
        await FavoritesService().removeFavorite(game.url);
        _snack('Removed from Library');
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !adding);
    }
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) _snack('Could not open $url');
  }

  void _copyMagnet(String magnet) {
    Clipboard.setData(ClipboardData(text: magnet));
    showDialog(
      context: context,
      builder: (_) => const SuccessActionDialog(
        title: 'Magnet link copied',
        subtitle: 'Paste it into your torrent client.',
        icon: LucideIcons.link,
      ),
    );
  }

  void _showAdultContentWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
              SizedBox(width: 8),
              Text('NSFW content', style: TextStyle(color: AppTheme.danger)),
            ],
          ),
          content: const Text(
            'This game contains adult content. Do you wish to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'I consent',
                style: TextStyle(color: AppTheme.danger),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                Navigator.pop(dialogContext);
                if (context.canPop()) context.pop();
              },
              child: const Text('Exit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMagnetExternally(String magnet) async {
    final ok = await launchUrl(Uri.parse(magnet));
    if (!ok) _copyMagnet(magnet);
  }

  /// Adds the torrent to the in-app engine, waits for its file list, lets
  /// the user pick files and starts the download.
  Future<void> _downloadTorrent({String? magnet, String? torrentUrl}) async {
    final game = _game!;
    final service = DownloadService();
    final existing = ref.read(downloadSessionProvider(game.title));
    if (existing != null && !existing.isTorrent) {
      _snack('This game is already downloading from direct links');
      return;
    }
    if (service.needsDownloadDirectory &&
        !await service.setDownloadDirectory()) {
      _snack('Download cancelled: no folder selected');
      return;
    }
    if (!await service.requestStoragePermission()) {
      _snack('Storage permission is required to save downloads');
      return;
    }

    String infoHash;
    try {
      final saveDir = await service.gameDirectory(game.title);
      infoHash = await _withProgress(
        'Starting torrent…',
        () => TorrentEngine().add(
          magnet: magnet,
          torrentUrl: torrentUrl,
          saveDir: saveDir,
        ),
      );
    } catch (e) {
      _snack('Could not start the torrent: $e');
      return;
    }
    if (!mounted) return;

    final status = await showDialog<TorrentStatus>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TorrentMetadataDialog(infoHash: infoHash),
    );
    if (status == null || !mounted) {
      if (existing == null) {
        unawaited(TorrentEngine().remove(infoHash).catchError((Object _) {}));
      }
      return;
    }

    final urls = [
      for (final f in status.files)
        TorrentInfo.fileUrl(status.infoHash, f.index, f.path),
    ];
    final selected = await context.push<List<String>>(
      '/select-files',
      extra: {
        'game': game,
        'fileUrls': urls,
        'fileSizes': {
          for (final f in status.files)
            TorrentInfo.fileUrl(status.infoHash, f.index, f.path): f.length,
        },
        if (existing != null) ...{
          'initialSelection': existing.selectedUrls,
          'completedFiles': existing.completedUrls,
        },
      },
    );
    if (selected == null || selected.isEmpty || !mounted) {
      if (existing == null) {
        unawaited(TorrentEngine().remove(infoHash).catchError((Object _) {}));
      }
      return;
    }

    try {
      if (mounted) await guideBackgroundDownloads(context);
      final result = await service.queueTorrent(
        gameTitle: game.title,
        coverUrl: game.coverUrl,
        gameUrl: game.url,
        totalGameSize: game.repackSize ?? game.size,
        status: status,
        selected: selected.map(TorrentInfo.fileIndex).whereType<int>().toList(),
      );
      _snack(
        result == QueueResult.merged
            ? 'Torrent selection updated'
            : 'Torrent download started (${selected.length} files)',
        action: SnackBarAction(
          label: 'VIEW',
          onPressed: () => openDownloadDetails(context, game.title),
        ),
      );
    } catch (e) {
      _snack('$e');
    }
  }

  /// Shows a modal spinner while [work] runs.
  Future<T> _withProgress<T>(String message, Future<T> Function() work) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    try {
      return await work();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// Turns a mirror entry into a list of downloadable file URLs, asks the user
  /// which ones to download, then queues them.
  Future<void> _onMirrorTap(String name, String value) async {
    if (value.isEmpty) return;

    List<String> files;
    final isDirectHost =
        value.contains('fuckingfast.co') || value.contains('datanodes.to');
    if (value.contains('\n')) {
      files = value
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (isDirectHost) {
      files = [value.trim()];
    } else if (name.contains('FuckingFast') || name.contains('DataNodes')) {
      // Link collection on a paste site.
      files = await _withProgress(
        'Fetching file list…',
        () => ScraperService().getPastebinLinks(value),
      );
    } else {
      files = await _withProgress(
        'Fetching file list…',
        () => ScraperService().getMirrorFileList(value),
      );
    }

    if (!mounted) return;
    if (files.isEmpty) {
      _snack('No downloadable files found — opening in browser');
      _launch(value);
      return;
    }

    final existing = ref.read(downloadSessionProvider(_game!.title));
    final selected = files.length == 1
        ? files
        : await context.push<List<String>>(
            '/select-files',
            extra: {
              'game': _game,
              'fileUrls': files,
              if (existing != null) ...{
                'initialSelection': existing.selectedUrls,
                'completedFiles': existing.completedUrls,
              },
            },
          );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _queue(selected, files);
  }

  Future<void> _queue(List<String> urls, List<String> allUrls) async {
    final service = DownloadService();
    if (service.needsDownloadDirectory) {
      final picked = await service.setDownloadDirectory();
      if (!picked) {
        _snack('Download cancelled: no folder selected');
        return;
      }
    }
    if (!await service.requestStoragePermission()) {
      _snack('Storage permission is required to save downloads');
      return;
    }

    final game = _game!;
    if (mounted) await guideBackgroundDownloads(context);
    final result = await service.queueGame(
      gameTitle: game.title,
      coverUrl: game.coverUrl,
      gameUrl: game.url,
      urls: urls,
      allUrls: allUrls,
      totalGameSize: game.repackSize ?? game.size,
      // Same files on the other mirrors, used if this mirror fails.
      alternates: {
        for (final u in urls) u: ScraperService.alternateMirrorsIn(game, u),
      },
    );
    if (!mounted) return;
    _snack(
      result == QueueResult.merged
          ? 'Added files to the existing download'
          : 'Download started (${urls.length} files)',
      action: SnackBarAction(
        label: 'VIEW',
        onPressed: () => openDownloadDetails(context, game.title),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const GameDetailsSkeleton();

    final game = _game;
    if (game == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.wifiOff, size: 44, color: Colors.white12),
              const SizedBox(height: 12),
              const Text('Could not load this game'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final session = ref.watch(downloadSessionProvider(game.title));
    final wide = context.isWide;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: wide
            ? null
            : Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
        actions: [
          IconButton(
            tooltip: _isFavorite ? 'Remove from Library' : 'Save to Library',
            icon: Icon(
              _isFavorite ? Icons.bookmark : Icons.bookmark_border,
              color: _isFavorite ? AppTheme.primaryGreen : null,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: 'Copy page link',
            icon: const Icon(LucideIcons.link),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: game.url));
              _snack('Link copied');
            },
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(LucideIcons.externalLink),
            onPressed: () => _launch(game.url),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            40,
          ),
          child: ContentConstraint(
            maxWidth: 1400,
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: context.windowSize == WindowSize.large
                            ? 380
                            : 330,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(aspectRatio: 0.72, child: _cover(game)),
                            const SizedBox(height: 20),
                            _downloadSection(game, session),
                          ],
                        ),
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _title(game),
                            const SizedBox(height: 16),
                            _infoTable(game),
                            const SizedBox(height: 24),
                            _Screenshots(images: _images(game)),
                            const SizedBox(height: 24),
                            _description(game),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _title(game),
                      const SizedBox(height: 16),
                      _Screenshots(images: _images(game)),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 104,
                            height: 150,
                            child: _cover(game),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: _infoTable(game)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _description(game),
                      const SizedBox(height: 24),
                      _downloadSection(game, session),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  List<String> _images(Game g) => g.screenshots.isNotEmpty
      ? g.screenshots
      : [if (g.coverUrl.isNotEmpty) g.coverUrl];

  Widget _cover(Game game) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: game.coverUrl.isEmpty
          ? Container(color: AppTheme.surfaceHighlight)
          : CachedNetworkImage(
              cacheManager: appImageCache,
              imageUrl: game.coverUrl,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  Container(color: AppTheme.surfaceHighlight),
            ),
    );
  }

  Widget _title(Game game) {
    final tags = (game.genre ?? '')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          game.title,
          style: TextStyle(
            fontSize: context.isWide ? 32 : 24,
            fontWeight: FontWeight.bold,
            height: 1.15,
          ),
        ),
        if (game.uploadDate != null) ...[
          const SizedBox(height: 6),
          Text(
            game.uploadDate!,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in tags) _Tag(t)],
          ),
        ],
      ],
    );
  }

  Widget _infoTable(Game game) {
    Widget row(String label, String? value, {Color? color, int lines = 2}) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: color ?? AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: lines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color ?? Colors.white70,
                  fontSize: 13,
                  fontWeight: color != null ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          'Repack size',
          game.repackSize ?? game.size,
          color: AppTheme.primaryGreen,
        ),
        row('Original size', game.originalSize),
        row('Company', game.companies),
        row('Languages', game.languages, lines: 3),
      ],
    );
  }

  Widget _description(Game game) {
    final text = game.description;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              icon: Icon(
                _descriptionExpanded
                    ? LucideIcons.chevronUp
                    : LucideIcons.chevronDown,
                size: 16,
              ),
              label: Text(_descriptionExpanded ? 'Show less' : 'Show more'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: SelectableText(
            text,
            maxLines: _descriptionExpanded ? null : 5,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  Widget _downloadSection(Game game, DownloadSession? session) {
    final direct = Map.fromEntries(
      game.mirrors.entries.where((e) => !_isTorrentSite(e.key)),
    );
    final torrentSites = Map.fromEntries(
      game.mirrors.entries.where((e) => _isTorrentSite(e.key)),
    );
    final hasTorrent =
        game.magnetLink != null ||
        game.torrentUrl != null ||
        torrentSites.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: AppTheme.primaryGreen, width: 4),
            ),
          ),
          child: const Text(
            'Download',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 14),
        if (session != null) ...[
          _ActiveDownloadCard(session: session),
          const SizedBox(height: 16),
        ],
        if (direct.isNotEmpty) ...[
          const _Label('DIRECT DOWNLOAD (IN-APP)'),
          for (final e in direct.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DownloadOptionTile(
                title: e.key,
                subtitle: _mirrorSubtitle(e.key, e.value),
                icon: e.key.contains('FuckingFast')
                    ? LucideIcons.zap
                    : LucideIcons.cloud,
                isPremium: e.key.contains('FuckingFast'),
                trailerIcon: LucideIcons.download,
                onTap: () => _onMirrorTap(e.key, e.value),
              ),
            ),
          const SizedBox(height: 16),
        ],
        if (hasTorrent) ...[
          const _Label('TORRENT'),
          if (game.magnetLink != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DownloadOptionTile(
                title: 'Magnet link',
                subtitle: _torrentInApp
                    ? 'Download in the app • pick files'
                    : 'Open in your torrent client',
                icon: LucideIcons.magnet,
                isRecommended: true,
                trailerIcon: _torrentInApp
                    ? LucideIcons.download
                    : LucideIcons.externalLink,
                onTap: () => _torrentInApp
                    ? _downloadTorrent(magnet: game.magnetLink)
                    : _openMagnetExternally(game.magnetLink!),
              ),
            ),
          if (game.magnetLink != null)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 4,
                children: [
                  if (_torrentInApp)
                    TextButton.icon(
                      onPressed: () => _openMagnetExternally(game.magnetLink!),
                      icon: const Icon(LucideIcons.externalLink, size: 14),
                      label: const Text('Open in torrent client'),
                    ),
                  TextButton.icon(
                    onPressed: () => _copyMagnet(game.magnetLink!),
                    icon: const Icon(LucideIcons.copy, size: 14),
                    label: const Text('Copy magnet'),
                  ),
                ],
              ),
            ),
          if (game.torrentUrl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DownloadOptionTile(
                title: '.torrent file',
                subtitle: _torrentInApp
                    ? 'Download in the app • pick files'
                    : 'Download via browser',
                icon: LucideIcons.fileDown,
                trailerIcon: _torrentInApp
                    ? LucideIcons.download
                    : LucideIcons.externalLink,
                onTap: () => _torrentInApp
                    ? _downloadTorrent(torrentUrl: game.torrentUrl)
                    : _launch(game.torrentUrl!),
              ),
            ),
          for (final e in torrentSites.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DownloadOptionTile(
                title: e.key,
                subtitle: 'Torrent tracker page',
                icon: LucideIcons.globe,
                trailerIcon: LucideIcons.externalLink,
                onTap: () => _launch(e.value),
              ),
            ),
        ],
        if (direct.isEmpty && !hasTorrent)
          const Text(
            'No download links were found on this page.',
            style: TextStyle(color: AppTheme.textMuted),
          ),
      ],
    );
  }

  static bool _isTorrentSite(String name) =>
      name.contains('1337x') ||
      name.contains('RuTor') ||
      name.contains('Tapochek');

  static String _mirrorSubtitle(String name, String value) {
    final count = value.contains('\n') ? value.split('\n').length : null;
    final speed = name.contains('FuckingFast') ? 'Fastest' : 'Direct link';
    return count != null ? '$speed • $count files' : speed;
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    final adult = label.toLowerCase() == 'adult';
    final color = adult ? AppTheme.danger : AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Shown on the game page when this game is already in the download list.
class _ActiveDownloadCard extends StatelessWidget {
  final DownloadSession session;
  const _ActiveDownloadCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusChip(status: s.status),
                const Spacer(),
                Text(
                  s.status == SessionStatus.downloading
                      ? formatSpeed(s.networkSpeed)
                      : '${(s.overallProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GreenProgressBar(value: s.overallProgress),
            const SizedBox(height: 6),
            Text(
              sessionProgressLabel(s),
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!s.isCompleted) PauseResumeButton(session: s),
                OutlinedButton.icon(
                  onPressed: () => openDownloadDetails(context, s.gameTitle),
                  icon: const Icon(LucideIcons.listChecks, size: 18),
                  label: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Screenshots extends StatefulWidget {
  final List<String> images;
  const _Screenshots({required this.images});

  @override
  State<_Screenshots> createState() => _ScreenshotsState();
}

class _ScreenshotsState extends State<_Screenshots> {
  final _controller = CarouselSliderController();
  int _index = 0;

  void _openViewer(int initial) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) =>
          _ImageViewer(images: widget.images, initialIndex: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    if (images.isEmpty) return const SizedBox.shrink();
    final wide = context.isWide;

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            CarouselSlider(
              carouselController: _controller,
              options: CarouselOptions(
                autoPlay: images.length > 1,
                autoPlayInterval: const Duration(seconds: 5),
                pauseAutoPlayOnTouch: true,
                aspectRatio: 16 / 9,
                viewportFraction: wide ? 1.0 : 0.92,
                enlargeCenterPage: !wide,
                enableInfiniteScroll: images.length > 1,
                onPageChanged: (i, _) => setState(() => _index = i),
              ),
              items: [
                for (var i = 0; i < images.length; i++)
                  MouseRegion(
                    cursor: SystemMouseCursors.zoomIn,
                    child: GestureDetector(
                      onTap: () => _openViewer(i),
                      child: Container(
                        margin: EdgeInsets.symmetric(horizontal: wide ? 0 : 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                          image: DecorationImage(
                            image: CachedNetworkImageProvider(
                              images[i],
                              cacheManager: appImageCache,
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (wide && images.length > 1) ...[
              Positioned(
                left: 8,
                child: _ArrowButton(
                  icon: LucideIcons.chevronLeft,
                  onTap: _controller.previousPage,
                ),
              ),
              Positioned(
                right: 8,
                child: _ArrowButton(
                  icon: LucideIcons.chevronRight,
                  onTap: _controller.nextPage,
                ),
              ),
            ],
          ],
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < images.length; i++)
                GestureDetector(
                  onTap: () => _controller.animateToPage(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _index == i ? 20 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: _index == i
                          ? AppTheme.primaryGreen
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

/// Full-screen screenshot viewer with zoom and keyboard navigation.
class _ImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _ImageViewer({required this.images, required this.initialIndex});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _page = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _go(int delta) => _page.animateToPage(
    ((_page.page?.round() ?? 0) + delta).clamp(0, widget.images.length - 1),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            PageView.builder(
              controller: _page,
              itemCount: widget.images.length,
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    cacheManager: appImageCache,
                    imageUrl: widget.images[i],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: _ArrowButton(
                icon: LucideIcons.x,
                onTap: () => Navigator.pop(context),
              ),
            ),
            if (widget.images.length > 1) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ArrowButton(
                    icon: LucideIcons.chevronLeft,
                    onTap: () => _go(-1),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _ArrowButton(
                    icon: LucideIcons.chevronRight,
                    onTap: () => _go(1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
