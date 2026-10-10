import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Clickable card surface with a desktop hover state (lift + green outline)
/// and a regular ink ripple on touch.
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Color color;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;

  const HoverCard({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.color = AppTheme.surfaceDark,
    this.padding,
    this.tooltip,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: _hovered
              ? AppTheme.primaryGreen.withValues(alpha: 0.6)
              : AppTheme.surfaceHighlight,
        ),
        boxShadow: _hovered
            ? [
                BoxShadow(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: widget.borderRadius,
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hovered = h),
          child: widget.padding == null
              ? widget.child
              : Padding(padding: widget.padding!, child: widget.child),
        ),
      ),
    );
    if (widget.tooltip != null) {
      card = Tooltip(message: widget.tooltip!, child: card);
    }
    return card;
  }
}
