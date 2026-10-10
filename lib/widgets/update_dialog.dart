import 'package:fitgirl_mobile_flutter/core/app_version.dart';
import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/core/utils/format.dart';
import 'package:fitgirl_mobile_flutter/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Checks for an update after startup and shows the prompt when the rules
/// in [UpdateService] allow it. Errors (offline etc.) are silent.
Future<void> promptForUpdateOnStartup(
  GlobalKey<NavigatorState> navigator,
) async {
  try {
    final check = await UpdateService().checkForStartupPrompt();
    final context = navigator.currentContext;
    if (check == null || context == null || !context.mounted) return;
    await showUpdateDialog(context, check);
  } catch (e) {
    debugPrint('Update check failed: $e');
  }
}

/// Manual "Check for updates" from Settings (ignores Later/Skip).
Future<void> checkForUpdatesManually(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final check = await UpdateService().check();
    if (!context.mounted) return;
    if (check == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            AppVersion.isRelease
                ? "You're on the latest version"
                : 'Updates are only available in release builds',
          ),
        ),
      );
      return;
    }
    await showUpdateDialog(context, check);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not check for updates: $e')),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, UpdateCheck check) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !check.forced,
    builder: (_) => _UpdateDialog(check: check),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateCheck check;
  const _UpdateDialog({required this.check});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress; // null = not downloading
  String? _error;
  bool _waitingForInstaller = false;

  AppRelease get _release => widget.check.latest;

  Future<void> _update() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await UpdateService().downloadAndInstall(
        _release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      if (UpdateService.installsAutomatically) {
        // Android shows the system installer on top of the app.
        setState(() => _waitingForInstaller = true);
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = widget.check.forced;
    final downloading = _progress != null && !_waitingForInstaller;
    final size = _release.asset?.size ?? 0;

    return PopScope(
      canPop: !forced && !downloading,
      child: AlertDialog(
        icon: Icon(
          forced ? LucideIcons.shieldAlert : LucideIcons.download,
          color: forced ? AppTheme.warning : AppTheme.primaryGreen,
          size: 32,
        ),
        title: Text(forced ? 'Update required' : 'Update available'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppVersion.label(widget.check.currentTag)}  →  ${AppVersion.label(_release.tag)}'
                '${size > 0 ? '   •   ${formatBytes(size)}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                forced
                    ? 'This version is ${widget.check.versionsBehind} releases behind and is no longer supported. Please update to continue.'
                    : widget.check.versionsBehind > 1
                    ? "You're ${widget.check.versionsBehind} releases behind."
                    : 'A new version is ready.',
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              if (_release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _plainNotes(_release.notes),
                      style: const TextStyle(fontSize: 12, height: 1.45),
                    ),
                  ),
                ),
              ],
              if (downloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _progress! > 0 ? _progress : null,
                ),
                const SizedBox(height: 6),
                Text(
                  'Downloading… ${(_progress! * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
              if (_waitingForInstaller) ...[
                const SizedBox(height: 16),
                const Text(
                  'Follow the installer to finish updating.',
                  style: TextStyle(color: AppTheme.primaryGreen),
                ),
              ],
              if (!UpdateService.installsAutomatically &&
                  _release.asset != null &&
                  !downloading) ...[
                const SizedBox(height: 12),
                const Text(
                  'The new version will be downloaded and shown in your file manager to install.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
              ],
            ],
          ),
        ),
        actions: downloading
            ? const []
            : [
                if (!forced) ...[
                  TextButton(
                    onPressed: () {
                      UpdateService().skip(_release.tag);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Skip this version',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      UpdateService().remindLater();
                      Navigator.pop(context);
                    },
                    child: const Text('Later'),
                  ),
                ],
                FilledButton.icon(
                  onPressed: _update,
                  icon: Icon(
                    _release.asset == null
                        ? LucideIcons.externalLink
                        : LucideIcons.download,
                    size: 18,
                  ),
                  label: Text(
                    _error != null
                        ? 'Retry'
                        : _waitingForInstaller
                        ? 'Open installer again'
                        : _release.asset == null
                        ? 'Open release page'
                        : 'Update now',
                  ),
                ),
              ],
      ),
    );
  }

  /// GitHub's generated notes are Markdown; show them as readable text.
  static String _plainNotes(String md) => md
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
      .trim();
}
