import 'dart:io' show Platform;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 window size classes.
enum WindowSize { compact, medium, expanded, large }

class Breakpoints {
  static const double medium = 600;
  static const double expanded = 900;
  static const double large = 1280;

  /// Max width of reading/content columns on big monitors.
  static const double maxContentWidth = 1600;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  WindowSize get windowSize {
    final w = screenWidth;
    if (w >= Breakpoints.large) return WindowSize.large;
    if (w >= Breakpoints.expanded) return WindowSize.expanded;
    if (w >= Breakpoints.medium) return WindowSize.medium;
    return WindowSize.compact;
  }

  bool get isCompact => windowSize == WindowSize.compact;

  /// Wide enough for side navigation and master/detail panes.
  bool get isWide => screenWidth >= Breakpoints.expanded;

  /// Horizontal page padding that grows with the window.
  double get pagePadding {
    switch (windowSize) {
      case WindowSize.compact:
        return 16;
      case WindowSize.medium:
        return 24;
      case WindowSize.expanded:
      case WindowSize.large:
        return 32;
    }
  }
}

bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Enables mouse/trackpad drag-scrolling (horizontal lists are otherwise
/// impossible to scroll with a mouse) and shows scrollbars on desktop.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

/// Centers [child] and caps its width so content doesn't stretch across
/// ultra-wide monitors.
class ContentConstraint extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentConstraint({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.maxContentWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Sliver version of [ContentConstraint] with responsive horizontal padding.
class SliverContent extends StatelessWidget {
  final Widget sliver;
  final double maxWidth;
  final EdgeInsets extraPadding;

  const SliverContent({
    super.key,
    required this.sliver,
    this.maxWidth = Breakpoints.maxContentWidth,
    this.extraPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final side = width > maxWidth ? (width - maxWidth) / 2 : 0.0;
        final pad = context.pagePadding;
        return SliverPadding(
          padding: EdgeInsets.only(
            left: side + pad + extraPadding.left,
            right: side + pad + extraPadding.right,
            top: extraPadding.top,
            bottom: extraPadding.bottom,
          ),
          sliver: sliver,
        );
      },
    );
  }
}

/// Large page title used at the top of each tab.
class PageHeader extends StatelessWidget {
  final String title;
  final String? overline;
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.overline,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        context.isWide ? 28 : 16,
        context.pagePadding,
        8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (overline != null)
                  Text(
                    overline!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
