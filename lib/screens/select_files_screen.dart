import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/file_item.dart';
import 'package:fitgirl_mobile_flutter/models/game.dart';
import 'package:fitgirl_mobile_flutter/widgets/download_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Lets the user choose which repack files to download.
///
/// When [initialSelection] is given the screen is in "manage" mode for an
/// existing download: completed files are locked and the result is applied
/// to the running download.
class SelectFilesScreen extends StatefulWidget {
  final Game game;
  final List<String> fileUrls;
  final List<String>? initialSelection;
  final List<String>? completedFiles;

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

class _Section {
  final String title;
  final IconData icon;
  final String emptyText;
  final List<FileItem> files = [];
  _Section(this.title, this.icon, this.emptyText);
}

class _SelectFilesScreenState extends State<SelectFilesScreen> {
  late final _Section _updates = _Section('Updates', LucideIcons.refreshCw, '');
  late final _Section _core = _Section('Core files', LucideIcons.package, '');
  late final _Section _languages = _Section(
    'Language packs',
    LucideIcons.languages,
    'No language packs for this repack',
  );
  late final _Section _optional = _Section(
    'Optional bonus',
    LucideIcons.plusCircle,
    'No optional files for this repack',
  );
  List<_Section> get _sections => [_updates, _core, _languages, _optional];
  Iterable<FileItem> get _allFiles => _sections.expand((s) => s.files);

  late final Set<String> _completed = widget.completedFiles?.toSet() ?? {};
  bool get _manageMode => widget.initialSelection != null;
  String _query = '';
  late int _bytesPerFile;

  static final _updateRegex = RegExp(
    r'(update|patch|fix)',
    caseSensitive: false,
  );
  static final _langRegex = RegExp(
    r'(selective|language|german|french|spanish|italian|russian|portuguese|'
    r'brazilian|japanese|chinese|korean|polish|traditional|simplified|arab)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _parseFiles();
    // "Repack Size: from 25 GB" is the size of the mandatory files, so it
    // gives a per-part estimate. FitGirl parts are mostly equal in size.
    final repack = parseSizeToBytes(widget.game.repackSize ?? widget.game.size);
    final mandatory = _core.files.length + _updates.files.length;
    _bytesPerFile = repack > 0 && mandatory > 0
        ? repack ~/ mandatory
        : 500 * 1024 * 1024;
  }

  void _parseFiles() {
    final preselected = widget.initialSelection?.toSet();
    var id = 0;
    final seen = <String>{};
    for (final raw in widget.fileUrls) {
      final url = raw.trim();
      if (url.isEmpty || !seen.add(url)) continue;
      final name = fileNameFromUrl(url);
      if (name.isEmpty) continue;
      final lower = name.toLowerCase();

      final isUpdate =
          _updateRegex.hasMatch(lower) && !lower.contains('setup-fitgirl');
      final isLang = !isUpdate && _langRegex.hasMatch(lower);
      final isOptional = !isUpdate && !isLang && lower.contains('optional');
      final tag = isUpdate
          ? 'UPDATE'
          : isLang
          ? 'LANG'
          : isOptional
          ? 'OPT'
          : 'REQ';

      final done = _completed.contains(url);
      final selected =
          done ||
          (preselected != null
              ? preselected.contains(url)
              : (tag == 'REQ' || tag == 'UPDATE'));

      final item = FileItem(
        id: '${++id}',
        name: name,
        size: '',
        required: done,
        selected: selected,
        tag: tag,
        url: url,
      );
      (isUpdate
              ? _updates
              : isLang
              ? _languages
              : isOptional
              ? _optional
              : _core)
          .files
          .add(item);
    }
  }

  int get _selectedCount => _allFiles.where((f) => f.selected).length;

  void _toggle(FileItem f) {
    if (_completed.contains(f.url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already downloaded — cannot deselect')),
      );
      return;
    }
    setState(() => f.selected = !f.selected);
  }

  void _setAll(Iterable<FileItem> files, bool value) {
    setState(() {
      for (final f in files) {
        if (!_completed.contains(f.url)) f.selected = value;
      }
    });
  }

  void _resetDefaults() {
    setState(() {
      for (final f in _allFiles) {
        f.selected =
            _completed.contains(f.url) || f.tag == 'REQ' || f.tag == 'UPDATE';
      }
    });
  }

  void _confirm() {
    final selected = _allFiles
        .where((f) => f.selected && f.url != null)
        .map((f) => f.url!)
        .toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least one file')));
      return;
    }
    // Keep the original part order.
    final order = {
      for (var i = 0; i < widget.fileUrls.length; i++)
        widget.fileUrls[i].trim(): i,
    };
    selected.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));
    context.pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    bool visible(FileItem f) =>
        query.isEmpty || f.name.toLowerCase().contains(query);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _confirm,
        const SingleActivator(LogicalKeyboardKey.escape): () => context.pop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back (Esc)',
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => context.pop(),
            ),
            title: Text(
              _manageMode ? 'Manage files' : 'Select files',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => _setAll(_allFiles, true),
                child: const Text('All'),
              ),
              TextButton(
                onPressed: _resetDefaults,
                child: const Text('Defaults'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ContentConstraint(
            maxWidth: 960,
            child: Column(
              children: [
                _buildGameHeader(),
                Expanded(
                  child: Scrollbar(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        context.pagePadding,
                        8,
                        context.pagePadding,
                        24,
                      ),
                      children: [
                        if (widget.fileUrls.length > 12)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              decoration: const InputDecoration(
                                hintText: 'Filter files by name',
                                prefixIcon: Icon(LucideIcons.search, size: 18),
                                isDense: true,
                              ),
                            ),
                          ),
                        for (final section in _sections)
                          if (section.files.isNotEmpty ||
                              section.emptyText.isNotEmpty)
                            _buildSection(
                              section,
                              section.files.where(visible).toList(),
                            ),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        8,
        context.pagePadding,
        8,
      ),
      child: Row(
        children: [
          CoverImage(
            url: widget.game.coverUrl,
            width: 48,
            height: 64,
            radius: 6,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.game.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.fileUrls.length} files available'
                  '${_completed.isNotEmpty ? ' · ${_completed.length} downloaded' : ''}',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(_Section section, List<FileItem> files) {
    final selectable = section.files.where((f) => !_completed.contains(f.url));
    final allSelected =
        selectable.isNotEmpty && selectable.every((f) => f.selected);
    final selectedHere = section.files.where((f) => f.selected).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(section.icon, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 8),
              Text(
                '${section.title.toUpperCase()}  ',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              if (section.files.isNotEmpty)
                Text(
                  '$selectedHere/${section.files.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              const Spacer(),
              if (selectable.isNotEmpty)
                TextButton(
                  onPressed: () => _setAll(section.files, !allSelected),
                  child: Text(allSelected ? 'Deselect all' : 'Select all'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (section.files.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                section.emptyText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                // Two columns of files on wide windows.
                final columns = c.maxWidth >= 760 ? 2 : 1;
                final width = (c.maxWidth - (columns - 1) * 8) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in files)
                      SizedBox(width: width, child: _buildFileTile(f)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFileTile(FileItem file) {
    final done = _completed.contains(file.url);
    final selected = file.selected;
    final tagColor = switch (file.tag) {
      'UPDATE' => Colors.orange,
      'LANG' => Colors.lightBlueAccent,
      'OPT' => Colors.purpleAccent,
      _ => AppTheme.textMuted,
    };

    return Material(
      color: AppTheme.surfaceDark,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggle(file),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryGreen.withValues(alpha: 0.35)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                done
                    ? LucideIcons.checkCircle2
                    : selected
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 20,
                color: done
                    ? AppTheme.primaryGreen.withValues(alpha: 0.6)
                    : selected
                    ? AppTheme.primaryGreen
                    : AppTheme.textMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: done ? Colors.white54 : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (done ? AppTheme.primaryGreen : tagColor).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  done ? 'DONE' : file.tag ?? '',
                  style: TextStyle(
                    color: done ? AppTheme.primaryGreen : tagColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final count = _selectedCount;
    final newCount = _allFiles
        .where((f) => f.selected && !_completed.contains(f.url))
        .length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        12,
        context.pagePadding,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundDark,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count of ${_allFiles.length} files selected',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '≈ ${formatBytes(newCount * _bytesPerFile)} to download',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: count == 0 ? null : _confirm,
            icon: Icon(
              _manageMode ? LucideIcons.check : LucideIcons.download,
              size: 18,
            ),
            label: Text(_manageMode ? 'Apply changes' : 'Download selected'),
          ),
        ],
      ),
    );
  }
}
