import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/models/file_item.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SelectFilesScreen extends StatefulWidget {
  final Game game;
  final List<String> fileUrls;
  final List<String>? initialSelection; // For existing sessions
  final List<String>? completedFiles; // Locked/Done files

  const SelectFilesScreen({
    super.key,
    required this.game,
    required this.fileUrls,
    this.initialSelection,
    this.completedFiles,
  });

  @override
  State<SelectFilesScreen> createState() => _SelectFilesScreenState();
}

class _SelectFilesScreenState extends State<SelectFilesScreen> {
  List<FileItem> _updatedFiles = [];
  List<FileItem> _coreFiles = [];
  List<FileItem> _languagePacks = [];
  List<FileItem> _optionalFiles = [];

  bool _showAllCore = false;

  @override
  void initState() {
    super.initState();
    _parseFiles();
  }

  void _parseFiles() {
    int idCounter = 0;

    // Regex for Updated Packs
    final updatedRegex = RegExp(r'(update|patch|fix)', caseSensitive: false);
    final langRegex = RegExp(
      r'(selective|language|german|french|spanish|italian|russian|portuguese|brazilian|japanese|chinese|korean|polish|traditional|simplified|arab)',
      caseSensitive: false,
    );

    // Prepare Sets for O(1) lookup
    final Set<String> selectionSet = widget.initialSelection?.toSet() ?? {};
    final Set<String> completedSet = widget.completedFiles?.toSet() ?? {};
    final bool hasPreSelection = widget.initialSelection != null;

    for (var url in widget.fileUrls) {
      var name = Uri.decodeFull(url.split('/').last.split('#').last);
      name = name.replaceAll('\n', '').trim();

      if (name.isEmpty) continue;

      final lowerName = name.toLowerCase();

      bool isUpdated =
          updatedRegex.hasMatch(lowerName) &&
          !lowerName.contains('setup-fitgirl');

      bool isLanguage = langRegex.hasMatch(lowerName);
      bool isOptional = lowerName.contains('optional');

      String? tag;
      if (isUpdated) {
        tag = 'UPDATE';
      } else if (isLanguage) {
        tag = 'LANG';
      } else if (isOptional) {
        tag = 'OPT';
      } else {
        tag = 'REQ'; // Core
      }

      // Selection Logic
      bool isSelected = false;
      bool isRequired = false; // "Visual" required

      if (completedSet.contains(url)) {
        isSelected = true;
        isRequired = true; // Lock it effectively
      } else if (hasPreSelection) {
        isSelected = selectionSet.contains(url);
      } else {
        // Default Logic for new games
        isSelected = (tag == 'REQ' || tag == 'UPDATE');
      }

      final item = FileItem(
        id: '${++idCounter}',
        name: name,
        size: '~500 MB',
        required:
            isRequired ||
            (tag == 'REQ' && !hasPreSelection), // Only force Req if new game
        selected: isSelected,
        tag: tag,
        url: url,
      );

      if (isUpdated) {
        _updatedFiles.add(item);
      } else if (isLanguage) {
        _languagePacks.add(item);
      } else if (isOptional) {
        _optionalFiles.add(item);
      } else {
        _coreFiles.add(item);
      }
    }
  }

  // Approx size calculation: Count * 500MB
  double get _totalSelectedSizeMB {
    int count = 0;
    for (var f in [
      ..._updatedFiles,
      ..._coreFiles,
      ..._languagePacks,
      ..._optionalFiles,
    ]) {
      if (f.selected) count++;
    }
    return count * 500.0;
  }

  String _formatSize(double mb) {
    if (mb >= 1024) {
      return '~${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '~${mb.toInt()} MB';
  }

  void _toggleFile(FileItem file) {
    // Prevent unchecking completed files
    if (widget.completedFiles != null &&
        widget.completedFiles!.contains(file.url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot deselect a completed file')),
      );
      return;
    }

    setState(() {
      file.selected = !file.selected;
    });
  }

  void _toggleSection(List<FileItem> files, bool select) {
    bool hasChanges = false;
    for (var f in files) {
      if (widget.completedFiles != null &&
          widget.completedFiles!.contains(f.url)) {
        continue; // Skip completed
      }
      f.selected = select;
      hasChanges = true;
    }
    if (hasChanges) setState(() {});
  }

  void _resetSelection() {
    if (widget.initialSelection != null) {
      // Reset to INITIAL state
      _parseFiles(); // Lazy reset?
      // Better to re-run parse logic or just reload screen?
      // Let's iterate and reset based on logic.
      setState(() {
        for (var f in [
          ..._coreFiles,
          ..._updatedFiles,
          ..._languagePacks,
          ..._optionalFiles,
        ]) {
          if (widget.completedFiles?.contains(f.url) ?? false) {
            f.selected = true; // Keep completed
            continue;
          }
          // If we are in "Manage Mode", reset might mean "Reset to stored state" OR "Reset to default defaults".
          // Let's assume user wants to reset to "Defaults" (Core checked, others unchecked)
          // BUT keep completed files checked.
          final isUpdated = f.tag == 'UPDATE';
          final isCore = f.tag == 'REQ';
          f.selected = isCore || isUpdated;
        }
      });
    } else {
      setState(() {
        for (var f in _coreFiles) f.selected = true;
        for (var f in _updatedFiles) f.selected = true;
        for (var f in _languagePacks) f.selected = false;
        for (var f in _optionalFiles) f.selected = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Select Files',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _resetSelection,
            child: const Text(
              'Reset',
              style: TextStyle(
                color: AppTheme.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildGameHeader(),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Updated Packs Section
                if (_updatedFiles.isNotEmpty) ...[
                  _buildSectionHeader(
                    'UPDATED PACKS',
                    LucideIcons.refreshCw,
                    _updatedFiles,
                  ),
                  ..._updatedFiles.map((f) => _buildFileTile(f)),
                  const SizedBox(height: 24),
                ],

                // Core Files Section (Collapsible)
                _buildCoreSection(),
                const SizedBox(height: 24),

                // Language Packs
                _buildSectionHeader(
                  'LANGUAGE PACKS',
                  LucideIcons.languages,
                  _languagePacks,
                ),
                if (_languagePacks.isEmpty)
                  _buildEmptyStateCard('No language packs available')
                else
                  ..._languagePacks.map((f) => _buildFileTile(f)),
                const SizedBox(height: 24),

                // Optional Bonus
                _buildSectionHeader(
                  'OPTIONAL BONUS',
                  LucideIcons.plusCircle,
                  _optionalFiles,
                ),
                if (_optionalFiles.isEmpty)
                  _buildEmptyStateCard('No optional bonus files available')
                else
                  ..._optionalFiles.map((f) => _buildFileTile(f)),
              ],
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildGameHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: widget.game.coverUrl,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.game.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.game.version ?? "v1.0"} • ${widget.game.genre ?? "Action"}',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'APPROX SIZE',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatSize(_totalSelectedSizeMB),
                style: const TextStyle(
                  color: AppTheme.primaryGreen,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoreSection() {
    final showAll = _showAllCore || _coreFiles.length <= 10;
    final displayFiles = showAll ? _coreFiles : _coreFiles.take(10).toList();

    return Column(
      children: [
        _buildSectionHeader('CORE FILES', LucideIcons.lock, _coreFiles),
        ...displayFiles.map((f) => _buildFileTile(f)),
        if (_coreFiles.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showAllCore = !_showAllCore;
                });
              },
              child: Text(
                _showAllCore ? 'Show Less' : 'Show All (${_coreFiles.length})',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    List<FileItem> files,
  ) {
    if (files.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      );
    }

    // Check if all are selected
    final allSelected = files.every((f) => f.selected);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => _toggleSection(files, !allSelected),
            child: Text(
              allSelected ? 'Deselect All' : 'Select All',
              style: const TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildFileTile(FileItem file) {
    return GestureDetector(
      onTap: () => _toggleFile(file),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: file.selected
                ? AppTheme.primaryGreen.withOpacity(0.3)
                : Colors.white10,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: file.selected
                    ? AppTheme.primaryGreen
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: file.selected ? AppTheme.primaryGreen : Colors.grey,
                  width: 1.5,
                ),
              ),
              child: file.selected
                  ? const Icon(Icons.check, size: 16, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Hide individual sizes for now as they are all ~500MB
                ],
              ),
            ),
            if (file.tag != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: file.tag == 'UPDATE'
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  file.tag!,
                  style: TextStyle(
                    color: file.tag == 'UPDATE'
                        ? Colors.orange
                        : Colors.grey[400],
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Selection Size',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatSize(_totalSelectedSizeMB),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                final selectedUrls =
                    [
                          ..._updatedFiles,
                          ..._coreFiles,
                          ..._languagePacks,
                          ..._optionalFiles,
                        ]
                        .where((f) => f.selected && f.url != null)
                        .map((f) => f.url!)
                        .toList();

                context.pop(selectedUrls);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(LucideIcons.download, size: 20),
              label: const Text(
                'Download Selected',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
