import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/services/scraper_service.dart';
import 'package:fitgirl_mobile_flutter/services/favorites_service.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/game_details_skeleton.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_option_tile.dart';
import 'package:fitgirl_mobile_flutter/widgets/success_action_dialog.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:ui';

class GameDetailsScreen extends StatefulWidget {
  final String? gameId;

  const GameDetailsScreen({super.key, this.gameId});

  @override
  State<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends State<GameDetailsScreen> {
  Game? _game;
  bool _isLoading = true;
  bool _isFavorite = false; // Add state
  int _currentCarouselIndex = 0;
  bool _isDescriptionExpanded = false;
  bool _isAutoPlay = true;
  Timer? _autoPlayTimer;

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadGameDetails();
  }

  Future<void> _loadGameDetails() async {
    // ... (existing null check)

    try {
      final scraper = ScraperService();
      // ... (fetching game)
      final game = await scraper.getGameDetails(widget.gameId!);

      if (mounted) {
        bool isFav = false;
        if (game != null) {
          isFav = await FavoritesService().isFavorite(game.url);
        }

        setState(() {
          _game = game;
          _isLoading = false;
          _isFavorite = isFav;
        });

        if (game != null &&
            (game.genre?.toLowerCase().contains('adult') ?? false)) {
          _showAdultContentWarning();
        }
      }
    } catch (e) {
      // ... (error handling)
    }
  }

  Future<void> _toggleFavorite() async {
    if (_game == null) return;

    // Optimistic update
    setState(() {
      _isFavorite = !_isFavorite;
    });

    try {
      if (_isFavorite) {
        await FavoritesService().addFavorite(_game!);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Added to Library')));
        }
      } else {
        await FavoritesService().removeFavorite(_game!.url);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Removed from Library')));
        }
      }
    } catch (e) {
      // Revert if error
      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch $url')));
      }
    }
  }

  void _copyMagnet(String magnet) {
    Clipboard.setData(ClipboardData(text: magnet));
    showDialog(
      context: context,
      builder: (c) => const SuccessActionDialog(
        title: 'Magnet Link Copied',
        subtitle: 'The magnet link has been copied to your clipboard.',
        icon: LucideIcons.link,
      ),
    );
  }

  void _downloadTorrent(String url) {
    // Simulate download
    showDialog(
      context: context,
      builder: (c) => const SuccessActionDialog(
        title: 'Torrent File Saved',
        subtitle: 'The .torrent file has been saved to your downloads folder.',
        icon: LucideIcons.fileDown,
      ),
    );
  }

  void _showAdultContentWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: AppTheme.surfaceDark,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('NSFW Content', style: TextStyle(color: Colors.red)),
            ],
          ),
          content: const Text(
            'This game contains adult content. Do you wish to proceed?',
            style: TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.pop(); // Pop dialog
              },
              child: const Text(
                'I Consent',
                style: TextStyle(color: Colors.red),
              ),
            ),
            FilledButton(
              onPressed: () {
                context.pop(); // Pop dialog
                context.pop(); // Pop screen
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Exit',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const GameDetailsSkeleton();
    }

    if (_game == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: const Center(
          child: Text('Game not found', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final images = _game!.screenshots.isNotEmpty
        ? _game!.screenshots
        : [_game!.coverUrl];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark.withOpacity(0.8),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.bookmark : Icons.bookmark_border,
              color: _isFavorite ? AppTheme.primaryGreen : Colors.white,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () {},
          ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
          child: ClipRect(child: Container(color: Colors.transparent)),
        ),
      ),
      body: SingleChildScrollView(
        // ...
        child: Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 60,
            bottom: 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _game!.title,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _game!.uploadDate ?? 'Unknown Date',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Carousel
              Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  CarouselSlider(
                    options: CarouselOptions(
                      autoPlay: _isAutoPlay,
                      autoPlayInterval: const Duration(seconds: 4),
                      aspectRatio: 16 / 9,
                      viewportFraction: 0.9,
                      enableInfiniteScroll: true,
                      enlargeCenterPage: true,
                      onPageChanged: (index, reason) {
                        setState(() {
                          _currentCarouselIndex = index;
                        });
                        if (reason == CarouselPageChangedReason.manual) {
                          setState(() {
                            _isAutoPlay = false;
                          });
                          _autoPlayTimer?.cancel();
                          _autoPlayTimer = Timer(
                            const Duration(seconds: 7),
                            () {
                              if (mounted) {
                                setState(() {
                                  _isAutoPlay = true;
                                });
                              }
                            },
                          );
                        }
                      },
                    ),
                    items: images.map((imageUrl) {
                      return Builder(
                        builder: (BuildContext context) {
                          return Container(
                            width: MediaQuery.of(context).size.width,
                            margin: const EdgeInsets.symmetric(horizontal: 5.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white10),
                              image: DecorationImage(
                                image: CachedNetworkImageProvider(imageUrl),
                                fit: BoxFit.cover,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 10,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (index) {
                          return Container(
                            width: _currentCarouselIndex == index ? 20.0 : 6.0,
                            height: 6.0,
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              color: _currentCarouselIndex == index
                                  ? AppTheme.primaryGreen
                                  : Colors.white.withOpacity(0.3),
                            ),
                          );
                        }),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),

              // Info Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cover Art
                    Container(
                      width: 100,
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(_game!.coverUrl),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (_game!.genre != null)
                                ..._game!.genre!
                                    .split(',')
                                    .map((g) => _buildTag(g.trim())),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_game!.companies != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildDetailRow(
                                'Company',
                                _game!.companies!,
                                valueColor: Colors.white70,
                                maxLines: 2,
                              ),
                            ),
                          if (_game!.languages != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: _buildDetailRow(
                                'Language',
                                _game!.languages!,
                                valueColor: Colors.white70,
                                maxLines: 3,
                              ),
                            ),
                          _buildDetailRow(
                            'Original Size',
                            _game!.originalSize ?? 'Unknown',
                            valueColor: Colors.white,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(
                                width: 70,
                                child: Text(
                                  'REPACK\nSIZE',
                                  style: TextStyle(
                                    color: AppTheme.primaryGreen,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _game!.repackSize ?? _game!.size,
                                  style: const TextStyle(
                                    color: AppTheme.primaryGreen,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Description Expandable
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isDescriptionExpanded
                                ? AppTheme.primaryGreen.withOpacity(0.3)
                                : Colors.white10,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isDescriptionExpanded
                                  ? 'Hide Description'
                                  : 'Show Description',
                              style: const TextStyle(
                                color: AppTheme.primaryGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isDescriptionExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: AppTheme.primaryGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isDescriptionExpanded && _game!.description != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceHighlight.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _game!.description!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Downloads Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: AppTheme.primaryGreen,
                            width: 4,
                          ),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Text(
                            'Download Options',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            LucideIcons.download,
                            color: AppTheme.primaryGreen,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Categorize mirrors
                    Builder(
                      builder: (context) {
                        final directMirrors = Map.fromEntries(
                          _game!.mirrors.entries.where(
                            (e) =>
                                !e.key.contains('1337x') &&
                                !e.key.contains('RuTor') &&
                                !e.key.contains('Tapochek'),
                          ),
                        );
                        final torrentMirrors = Map.fromEntries(
                          _game!.mirrors.entries.where(
                            (e) =>
                                e.key.contains('1337x') ||
                                e.key.contains('RuTor') ||
                                e.key.contains('Tapochek'),
                          ),
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Mirrors (Direct Links)
                            if (directMirrors.isNotEmpty) ...[
                              const Text(
                                'MIRRORS (DIRECT LINKS)',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...directMirrors.entries.map((entry) {
                                bool isPremium = entry.key.contains(
                                  'FuckingFast',
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: DownloadOptionTile(
                                    title: entry.key,
                                    subtitle: isPremium
                                        ? 'Ultra Fast Speed • Premium'
                                        : 'Direct Link',
                                    icon: isPremium
                                        ? LucideIcons.zap
                                        : LucideIcons.cloud,
                                    isPremium: isPremium,
                                    onTap: () async {
                                      if (entry.value.isNotEmpty) {
                                        // Show loading dialog
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (c) => const Center(
                                            child: CircularProgressIndicator(
                                              color: AppTheme.primaryGreen,
                                            ),
                                          ),
                                        );

                                        try {
                                          // 0. FAST PATH: Check for multiple direct links (newline separated)
                                          if (entry.value.contains('\n')) {
                                            final urls = entry.value.split(
                                              '\n',
                                            );
                                            Navigator.pop(
                                              context,
                                            ); // Close loading dialog

                                            final selectedFiles = await context
                                                .push<List<String>>(
                                                  '/select-files',
                                                  extra: {
                                                    'game': _game,
                                                    'fileUrls': urls,
                                                  },
                                                );

                                            if (selectedFiles != null &&
                                                selectedFiles.isNotEmpty) {
                                              _processSelectedDownloads(
                                                selectedFiles,
                                                urls,
                                              );
                                            }
                                            return;
                                          }

                                          // 1. Check for Indirect/Pastebin Links for Direct Hosts
                                          if ((entry.key.contains(
                                                    'FuckingFast',
                                                  ) &&
                                                  !entry.value.contains(
                                                    'fuckingfast.co',
                                                  )) ||
                                              (entry.key.contains(
                                                    'DataNodes',
                                                  ) &&
                                                  !entry.value.contains(
                                                    'datanodes.to',
                                                  ))) {
                                            // Scrape the pastebin for the actual FF/DN links
                                            final links = await ScraperService()
                                                .getPastebinLinks(entry.value);

                                            if (context.mounted) {
                                              Navigator.pop(
                                                context,
                                              ); // Close loading dialog

                                              if (links.isNotEmpty) {
                                                // Navigate to Select Files with the scraped Intermediate Links
                                                final selectedFiles =
                                                    await context
                                                        .push<List<String>>(
                                                          '/select-files',
                                                          extra: {
                                                            'game': _game,
                                                            'fileUrls': links,
                                                          },
                                                        );

                                                if (selectedFiles != null &&
                                                    selectedFiles.isNotEmpty) {
                                                  // User selected files and clicked "Save Selection" (we'll treat as Download)
                                                  // Now we need to process these downloads
                                                  _processSelectedDownloads(
                                                    selectedFiles,
                                                    links,
                                                  );
                                                }
                                                return;
                                              } else {
                                                // Scrape failed or empty, fallback to browser
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Could not parse link collection, opening in browser...',
                                                    ),
                                                  ),
                                                );
                                                _launchUrl(entry.value);
                                                return;
                                              }
                                            }
                                          }

                                          // 1. Try Direct Download Extraction (FuckingFast, DataNodes)
                                          if (entry.value.contains(
                                                'fuckingfast.co',
                                              ) ||
                                              entry.value.contains(
                                                'datanodes.to',
                                              )) {
                                            final directLink =
                                                await ScraperService()
                                                    .getDirectDownloadLink(
                                                      entry.value,
                                                    );

                                            if (context.mounted) {
                                              if (directLink != null) {
                                                Navigator.pop(
                                                  context,
                                                ); // Close loading
                                                _launchUrl(directLink);
                                                return; // Done
                                              } else {
                                                // If extraction failed, open original link directly
                                                // Do NOT fall through to getMirrorFileList as these are not file lists
                                                if (Navigator.canPop(context)) {
                                                  Navigator.pop(context);
                                                }
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Could not extract direct link, opening in browser...',
                                                    ),
                                                  ),
                                                );
                                                _launchUrl(entry.value);
                                                return;
                                              }
                                            }
                                          }

                                          // 2. Try Scraper for File Lists (MultiUp, etc.)
                                          final files = await ScraperService()
                                              .getMirrorFileList(entry.value);

                                          if (context.mounted) {
                                            if (Navigator.canPop(context)) {
                                              Navigator.pop(
                                                context,
                                              ); // Close loading
                                            }

                                            if (files.isNotEmpty) {
                                              final selectedFiles =
                                                  await context
                                                      .push<List<String>>(
                                                        '/select-files',
                                                        extra: {
                                                          'game': _game,
                                                          'fileUrls': files,
                                                        },
                                                      );

                                              if (selectedFiles != null &&
                                                  selectedFiles.isNotEmpty) {
                                                _processSelectedDownloads(
                                                  selectedFiles,
                                                  files,
                                                );
                                              }
                                            } else {
                                              // If scraped list is empty, open original link
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Opening link directly...',
                                                  ),
                                                ),
                                              );
                                              _launchUrl(entry.value);
                                            }
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            if (Navigator.canPop(context)) {
                                              Navigator.pop(
                                                context,
                                              ); // Close loading
                                            }
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text('Error: $e'),
                                              ),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                );
                              }),
                              const SizedBox(height: 24),
                            ],

                            // Mirrors (Torrent)
                            if (_game!.magnetLink != null ||
                                _game!.torrentUrl != null ||
                                torrentMirrors.isNotEmpty) ...[
                              const Text(
                                'MIRRORS (TORRENT)',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_game!.magnetLink != null)
                                DownloadOptionTile(
                                  title: 'Magnet Link',
                                  subtitle: 'Recommended',
                                  icon: LucideIcons.link,
                                  isRecommended: true,
                                  trailerIcon: LucideIcons.externalLink,
                                  onTap: () {
                                    if (_game!.magnetLink != null) {
                                      _copyMagnet(_game!.magnetLink!);
                                    }
                                  },
                                ),
                              const SizedBox(height: 8),
                              if (_game!.torrentUrl != null)
                                DownloadOptionTile(
                                  title: '.torrent File',
                                  subtitle: 'Direct Download',
                                  icon: LucideIcons.file,
                                  trailerIcon: LucideIcons.download,
                                  onTap: () {
                                    if (_game!.torrentUrl != null) {
                                      _downloadTorrent(_game!.torrentUrl!);
                                    }
                                  },
                                ),
                              // Add Torrent Sites (1337x, RuTor) here
                              ...torrentMirrors.entries.map((entry) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: DownloadOptionTile(
                                    title: entry.key,
                                    subtitle: 'Torrent Tracker',
                                    icon: LucideIcons
                                        .globe, // Distinct icon for web links
                                    trailerIcon: LucideIcons.externalLink,
                                    onTap: () {
                                      if (entry.value.isNotEmpty) {
                                        _launchUrl(entry.value);
                                      }
                                    },
                                  ),
                                );
                              }),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String label) {
    print('Checking tag: $label');
    bool isAdult = label.toLowerCase() == 'adult';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isAdult
            ? Colors.red.withOpacity(0.1)
            : AppTheme.primaryGreen.withOpacity(0.1),
        border: Border.all(
          color: isAdult
              ? Colors.red.withOpacity(0.3)
              : AppTheme.primaryGreen.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isAdult ? Colors.red : AppTheme.primaryGreen,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color valueColor = Colors.white,
    int? maxLines = 1,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            maxLines: maxLines,
            overflow: maxLines == 1 ? TextOverflow.ellipsis : null,
          ),
        ),
      ],
    );
  }

  Future<void> _processSelectedDownloads(
    List<String> urls,
    List<String> allUrls,
  ) async {
    if (urls.isEmpty) return;

    // Ensure download directory is set
    final downloadService = DownloadService();
    await downloadService.initialize();

    // Check if directory is invalid or not set
    final currentDir = await downloadService.downloadDirectory;
    if (currentDir == null) {
      if (mounted) {
        bool set = await downloadService.setDownloadDirectory();
        if (!set && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Download cancelled: No directory selected'),
            ),
          );
          return;
        }
      }
    }

    // Show loading dialog for resolution
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AppTheme.surfaceDark,
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppTheme.primaryGreen),
                SizedBox(height: 16),
                Text(
                  'Queuing downloads...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (urls.isNotEmpty) {
        // Queue the entire game session
        await downloadService.queueGame(
          gameTitle: _game?.title ?? "Unknown",
          coverUrl: _game?.coverUrl ?? "",
          urls: urls,
          totalGameSize: _game?.size ?? "TBD",
          allUrls: allUrls,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Downloads queued successfully!')),
          );
          Navigator.pop(context); // Close dialog
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No files selected')));
      }
    } catch (e) {
      if (e.toString().contains('Storage permission denied')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please grant Storage Permissions to download files.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        print('Error queuing game: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}
