import 'dart:io';

import 'package:fitgirl_mobile_flutter/core/app_version.dart';
import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'package:fitgirl_mobile_flutter/services/download_service.dart';
import 'package:fitgirl_mobile_flutter/services/settings_service.dart';
import 'package:fitgirl_mobile_flutter/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _resolvedRoot;

  @override
  void initState() {
    super.initState();
    _refreshRoot();
  }

  Future<void> _refreshRoot() async {
    final root = await DownloadService().downloadRoot();
    if (mounted) setState(() => _resolvedRoot = root);
  }

  void _update(AppSettings Function(AppSettings) fn) {
    SettingsService().update(fn(SettingsService().value));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final service = DownloadService();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const ContentConstraint(
              maxWidth: 880,
              child: PageHeader(title: 'Settings', overline: 'PREFERENCES'),
            ),
            ContentConstraint(
              maxWidth: 880,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Section(
                      title: 'Storage',
                      children: [
                        ListTile(
                          leading: const Icon(LucideIcons.folder),
                          title: const Text('Download folder'),
                          subtitle: Text(
                            settings.downloadPath ??
                                (_resolvedRoot != null
                                    ? '$_resolvedRoot (default)'
                                    : 'Not set'),
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: () async {
                            if (await service.setDownloadDirectory()) {
                              _refreshRoot();
                            }
                          },
                        ),
                        if (service.canOpenFolders && _resolvedRoot != null)
                          ListTile(
                            leading: const Icon(LucideIcons.folderOpen),
                            title: const Text('Open download folder'),
                            onTap: () async {
                              final dir = Directory(
                                '$_resolvedRoot${Platform.pathSeparator}FitGirl_Games',
                              );
                              await dir.create(recursive: true);
                              await launchUrl(Uri.directory(dir.path));
                            },
                          ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Each game is saved to FitGirl_Games/<game name> inside this folder. '
                            'Changing it only affects files that have not started yet.',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Downloads',
                      children: [
                        _SliderTile(
                          icon: LucideIcons.layers,
                          title: 'Parallel downloads',
                          subtitle:
                              'Files downloaded at the same time across all games',
                          value: settings.maxConcurrent,
                          min: 1,
                          max: 6,
                          onChanged: (v) =>
                              _update((s) => s.copyWith(maxConcurrent: v)),
                        ),
                        _SliderTile(
                          icon: LucideIcons.rotateCcw,
                          title: 'Automatic retries',
                          subtitle:
                              'Retries per file with a fresh link before marking it failed',
                          value: settings.autoRetries,
                          min: 0,
                          max: 10,
                          onChanged: (v) =>
                              _update((s) => s.copyWith(autoRetries: v)),
                        ),
                        SwitchListTile(
                          secondary: const Icon(LucideIcons.listOrdered),
                          title: const Text('One game at a time'),
                          subtitle: const Text(
                            'Finish a game before starting the next one in the queue',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                          value: settings.oneGameAtATime,
                          onChanged: (v) =>
                              _update((s) => s.copyWith(oneGameAtATime: v)),
                        ),
                      ],
                    ),
                    _Section(
                      title: 'Notifications',
                      children: [
                        SwitchListTile(
                          secondary: const Icon(LucideIcons.bell),
                          title: const Text('Game finished / failed alerts'),
                          subtitle: const Text(
                            'Shows a system notification when a game finishes or a file fails',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                          value: settings.notificationsEnabled,
                          onChanged: (v) => _update(
                            (s) => s.copyWith(notificationsEnabled: v),
                          ),
                        ),
                        if (Platform.isAndroid ||
                            Platform.isIOS ||
                            Platform.isMacOS)
                          ListTile(
                            leading: const Icon(LucideIcons.shieldCheck),
                            title: const Text('Grant permissions'),
                            subtitle: const Text(
                              'Notifications, background running and storage access',
                              style: TextStyle(color: AppTheme.textMuted),
                            ),
                            onTap: service.ensureBackgroundPermissions,
                          ),
                      ],
                    ),
                    _Section(
                      title: 'Keyboard shortcuts',
                      visible: isDesktopPlatform,
                      children: const [
                        _ShortcutRow('Ctrl + 1 … 5', 'Switch between tabs'),
                        _ShortcutRow('Ctrl + F', 'Search'),
                      ],
                    ),
                    _Section(
                      title: 'About',
                      children: [
                        const ListTile(
                          leading: Icon(LucideIcons.info),
                          title: Text('FitGirl Downloader'),
                          subtitle: Text(
                            'Unofficial fan-made client. Not affiliated with FitGirl Repacks.',
                            style: TextStyle(color: AppTheme.textMuted),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(LucideIcons.refreshCw),
                          title: const Text('Check for updates'),
                          subtitle: Text(
                            'Version ${AppVersion.label(AppVersion.current)}',
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                          onTap: () => checkForUpdatesManually(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool visible;
  const _Section({
    required this.title,
    required this.children,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16)),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$value',
                  style: const TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            label: '$value',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final String keys;
  final String action;
  const _ShortcutRow(this.keys, this.action);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(LucideIcons.keyboard),
      title: Text(action),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHighlight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          keys,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
