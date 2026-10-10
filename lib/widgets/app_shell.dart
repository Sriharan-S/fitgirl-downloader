import 'package:fitgirl_mobile_flutter/core/layout/responsive.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/models/download_session.dart';
import 'package:fitgirl_mobile_flutter/providers/download_provider.dart';
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
        // Fixed Material bar: every item keeps the same size and always
        // shows its label; selection only changes the colour (no growing
        // indicator or label animation).
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: navigationShell.currentIndex,
            onTap: _go,
            backgroundColor: AppTheme.surfaceDark,
            elevation: 0,
            selectedItemColor: AppTheme.primaryGreen,
            unselectedItemColor: AppTheme.textMuted,
            iconSize: 22,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            showSelectedLabels: true,
            showUnselectedLabels: true,
            items: [
              for (var i = 0; i < _destinations.length; i++)
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _BadgedIcon(
                      icon: _destinations[i].icon,
                      count: i == _downloadsIndex ? active.length : 0,
                    ),
                  ),
                  label: _destinations[i].label,
                  tooltip: '',
                ),
            ],
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Focus(autofocus: true, child: body),
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
