import 'dart:io';

import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Android lets the app run without battery restrictions.
Future<bool> isBackgroundUnrestricted() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  try {
    return await Permission.ignoreBatteryOptimizations.isGranted;
  } catch (_) {
    return true;
  }
}

/// Explains why downloads need unrestricted battery use and helps set it.
/// Called when a download starts; [force] shows it even if already asked
/// today (Settings).
Future<void> guideBackgroundDownloads(
  BuildContext context, {
  bool force = false,
}) async {
  if (kIsWeb || !Platform.isAndroid) return;
  if (!force && await isBackgroundUnrestricted()) return;

  const key = 'battery_guide_last_shown';
  final prefs = await SharedPreferences.getInstance();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  if (!force && prefs.getString(key) == today) return;
  await prefs.setString(key, today);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(
        LucideIcons.batteryCharging,
        color: AppTheme.primaryGreen,
      ),
      title: const Text('Keep downloads running'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Android pauses apps in the background to save battery, which '
            'stops long downloads. Set battery usage to Unrestricted:',
          ),
          SizedBox(height: 12),
          _Step('1', 'Tap "Allow" and confirm the system prompt.'),
          _Step(
            '2',
            'If downloads still stop: tap "Battery settings" → Battery → '
                'choose Unrestricted.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Later'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await openAppSettings();
          },
          child: const Text('Battery settings'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(dialogContext);
            await Permission.ignoreBatteryOptimizations.request();
          },
          child: const Text('Allow'),
        ),
      ],
    ),
  );
}

class _Step extends StatelessWidget {
  final String number;
  final String text;
  const _Step(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: AppTheme.primaryGreen,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
