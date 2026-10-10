import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class _Destination {
  final IconData icon;
  final String label;
  const _Destination(this.icon, this.label);
}

const _destinations = [
  _Destination(LucideIcons.home, 'Discover'),
  _Destination(LucideIcons.search, 'Search'),
  _Destination(LucideIcons.library, 'Library'),
  _Destination(LucideIcons.download, 'Downloads'),
  _Destination(LucideIcons.settings, 'Settings'),
];

const int _downloadsIndex = 3;

/// Root layout: bottom navigation on phones, sidebar on tablets/desktop.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(downloadsProvider);
    final active = sessions.where((s) => !s.isCompleted).toList();
    final speed = active.fold<double>(0, (s, e) => s + e.networkSpeed);

    final shortcuts = <ShortcutActivator, VoidCallback>{
      for (var i = 0; i < _destinations.length; i++)
        SingleActivator(
          LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i),
          control: true,
        ): () =>
            _go(i),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
          _go(1),
    };

    final Widget body;
    if (context.isWide) {
      body = Scaffold(
        body: Row(
          children: [
            _Sidebar(
              currentIndex: navigationShell.currentIndex,
              onSelect: _go,
              activeSessions: active,
              speed: speed,
              extended: context.windowSize == WindowSize.large,
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    } else {
      body = Scaffold(
        body: navigationShell,
        bottomNavigationBar: _ChipNavBar(
          currentIndex: navigationShell.currentIndex,
          onSelect: _go,
          downloadsBadge: active.length,
        ),
      );
    }

    // Back: inner pages pop as usual (the tab's own navigator handles them
    // first). On a tab's root, go to Discover; on Discover, confirm exit.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(context, sessions);
      },
      child: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(autofocus: true, child: body),
      ),
    );
  }

  Future<void> _onBack(
    BuildContext context,
    List<DownloadSession> sessions,
  ) async {
    if (navigationShell.currentIndex != 0) {
      _go(0);
      return;
    }
    final running = sessions.any((s) => !s.isCompleted && !s.isPaused);
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit FitGirl Downloader?'),
        content: Text(
          running
              ? 'Downloads keep running in the background.'
              : 'You can come back any time.',
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (exit != true) return;
    if (running && Platform.isAndroid) {
      // Leave the app without closing it so downloads continue.
      await const MethodChannel(
        'fitgirl/native',
      ).invokeMethod('moveTaskToBack');
    } else {
      await SystemNavigator.pop();
    }
  }
}

/// Bottom navigation: every item has the same width and always shows its
/// icon and name; the selected one sits inside a filled pill (chip). No
/// size or position changes on selection, only colours.
class _ChipNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final int downloadsBadge;

  const _ChipNavBar({
    required this.currentIndex,
    required this.onSelect,
    required this.downloadsBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceDark,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                for (var i = 0; i < _destinations.length; i++)
                  Expanded(
                    child: _ChipNavItem(
                      destination: _destinations[i],
                      selected: i == currentIndex,
                      badge: i == _downloadsIndex ? downloadsBadge : 0,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipNavItem extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _ChipNavItem({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.black : AppTheme.textMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Material(
          color: selected ? AppTheme.primaryGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  backgroundColor: selected
                      ? Colors.black
                      : AppTheme.primaryGreen,
                  textColor: selected ? AppTheme.primaryGreen : Colors.black,
                  label: Text('$badge'),
                  child: Icon(destination.icon, size: 21, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgedIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgedIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppTheme.primaryGreen,
      textColor: Colors.black,
      label: Text('$count'),
      child: Icon(icon),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<DownloadSession> activeSessions;
  final double speed;
  final bool extended;

  const _Sidebar({
    required this.currentIndex,
    required this.onSelect,
    required this.activeSessions,
    required this.speed,
    required this.extended,
  });

  @override
  Widget build(BuildContext context) {
    final width = extended ? 240.0 : 84.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      color: AppTheme.surfaceDark,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 24, 12, 24),
              child: Row(
                mainAxisAlignment: extended
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 40,
                      height: 40,
                      cacheWidth: 120,
                      errorBuilder: (_, _, _) => const Icon(
                        LucideIcons.gamepad2,
                        color: AppTheme.primaryGreen,
                        size: 32,
                      ),
                    ),
                  ),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FitGirl',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Downloader',
                            style: TextStyle(
                              color: AppTheme.primaryGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            for (var i = 0; i < _destinations.length; i++)
              _SidebarItem(
                destination: _destinations[i],
                selected: currentIndex == i,
                extended: extended,
                badge: i == _downloadsIndex ? activeSessions.length : 0,
                shortcut: 'Ctrl+${i + 1}',
                onTap: () => onSelect(i),
              ),
            const Spacer(),
            if (activeSessions.isNotEmpty)
              _MiniDownloadStatus(
                sessions: activeSessions,
                speed: speed,
                extended: extended,
                onTap: () => onSelect(_downloadsIndex),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final _Destination destination;
  final bool selected;
  final bool extended;
  final int badge;
  final String shortcut;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.extended,
    required this.badge,
    required this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primaryGreen : AppTheme.textMuted;
    final item = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected
            ? AppTheme.primaryGreen.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: extended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                if (extended) const SizedBox(width: 14),
                IconTheme(
                  data: IconThemeData(color: color, size: 22),
                  child: _BadgedIcon(icon: destination.icon, count: badge),
                ),
                if (extended) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: TextStyle(
                        color: selected ? Colors.white : AppTheme.textMuted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: extended ? shortcut : '${destination.label}  ($shortcut)',
      preferBelow: false,
      child: item,
    );
  }
}

class _MiniDownloadStatus extends StatelessWidget {
  final List<DownloadSession> sessions;
  final double speed;
  final bool extended;
  final VoidCallback onTap;

  const _MiniDownloadStatus({
    required this.sessions,
    required this.speed,
    required this.extended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        sessions.fold<double>(0, (s, e) => s + e.overallProgress) /
        sessions.length;
    final downloading = sessions.any(
      (s) => s.status == SessionStatus.downloading,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: AppTheme.surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: extended
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            downloading
                                ? LucideIcons.arrowDownCircle
                                : LucideIcons.pauseCircle,
                            size: 16,
                            color: downloading
                                ? AppTheme.primaryGreen
                                : AppTheme.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${sessions.length} active',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            formatSpeed(speed),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primaryGreen,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          backgroundColor: const Color(0xFF2A2A2A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatSpeed(speed),
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
