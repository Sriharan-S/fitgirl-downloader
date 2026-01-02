import 'package:flutter/material.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:lucide_icons/lucide_icons.dart';

class DownloadOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isRecommended;
  final bool isPremium;
  final IconData? trailerIcon;

  const DownloadOptionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isRecommended = false,
    this.isPremium = false,
    this.trailerIcon,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors based on state
    final Color borderColor = isPremium
        ? Colors.amber
        : (isRecommended ? AppTheme.primaryGreen : Colors.white10);

    final Color backgroundColor = isPremium
        ? const Color(0xFF1A1A0A)
        : (isRecommended ? const Color(0xFF0A150A) : AppTheme.surfaceDark);

    final Color primaryColor = isPremium
        ? Colors.amber
        : (isRecommended ? AppTheme.primaryGreen : Colors.grey);

    final Color subtitleColor = isPremium
        ? Colors.amber.withOpacity(0.7)
        : (isRecommended ? AppTheme.primaryGreen : Colors.grey[600]!);

    final Color iconBgColor = isPremium
        ? Colors.amber.withOpacity(0.1)
        : (isRecommended
              ? AppTheme.primaryGreen.withOpacity(0.1)
              : Colors.white10);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: primaryColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isPremium ? Colors.amber : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                trailerIcon ?? LucideIcons.externalLink,
                color: primaryColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
