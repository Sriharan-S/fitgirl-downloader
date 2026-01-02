import 'package:flutter/material.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';

class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const HeaderIconButton({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.surfaceHighlight),
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}
