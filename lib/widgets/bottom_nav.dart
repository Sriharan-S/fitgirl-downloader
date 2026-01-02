import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BottomNav extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const BottomNav({super.key, required this.navigationShell});

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onTap,
      destinations: const [
        NavigationDestination(icon: Icon(LucideIcons.home), label: 'Discover'),
        NavigationDestination(icon: Icon(LucideIcons.search), label: 'Search'),
        NavigationDestination(
          icon: Icon(LucideIcons.library),
          label: 'Library',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.download),
          label: 'Downloads',
        ),
      ],
    );
  }
}
