import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/services/browser_resolver.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Hosts the WebView used by [BrowserResolver]. It sits underneath the app
/// (so it works but isn't seen) and comes to the front only when the file
/// host asks for a human check.
class BrowserHost extends StatelessWidget {
  final Widget child;
  const BrowserHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrowserJob?>(
      valueListenable: BrowserResolver().job,
      builder: (context, job, _) {
        if (job == null) return child;
        return ValueListenableBuilder<bool>(
          valueListenable: job.visible,
          builder: (context, visible, _) {
            final web = WebViewWidget(controller: job.controller);
            return Stack(
              children: [
                // Hidden: a phone-sized page behind the app content.
                if (!visible)
                  Positioned(
                    left: 0,
                    top: 0,
                    width: 400,
                    height: 760,
                    child: IgnorePointer(child: web),
                  ),
                child,
                if (visible) _VerifySheet(job: job, web: web),
              ],
            );
          },
        );
      },
    );
  }
}

class _VerifySheet extends StatelessWidget {
  final BrowserJob job;
  final Widget web;
  const _VerifySheet({required this.job, required this.web});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: AppTheme.backgroundDark,
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  LucideIcons.shieldCheck,
                  color: AppTheme.primaryGreen,
                ),
                title: Text('Verify to continue (${job.host})'),
                subtitle: const Text(
                  'The file host wants to check you are human. Complete the '
                  'check below; the download continues automatically.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: job.cancel,
                  child: const Text('Cancel'),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: web),
            ],
          ),
        ),
      ),
    );
  }
}
