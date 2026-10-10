import 'dart:async';

import 'package:fitgirl_mobile_flutter/core/theme/app_theme.dart';
import 'package:fitgirl_mobile_flutter/services/torrent_engine.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Waits for a torrent's file list (magnets fetch it from peers first).
/// Pops with the [TorrentStatus] once known, or null when cancelled.
class TorrentMetadataDialog extends StatefulWidget {
  final String infoHash;
  const TorrentMetadataDialog({super.key, required this.infoHash});

  @override
  State<TorrentMetadataDialog> createState() => _TorrentMetadataDialogState();
}

class _TorrentMetadataDialogState extends State<TorrentMetadataDialog> {
  Timer? _timer;
  TorrentStatus? _status;
  String? _error;
  final _started = DateTime.now();

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final status = await TorrentEngine().get(widget.infoHash);
      if (!mounted) return;
      if (status.hasMetadata) {
        _timer?.cancel();
        Navigator.of(context).pop(status);
        return;
      }
      setState(() {
        _status = status;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final waited = DateTime.now().difference(_started).inSeconds;
    final peers = _status?.peers ?? 0;
    final known = _status?.knownPeers ?? 0;
    return AlertDialog(
      icon: const Icon(LucideIcons.magnet, color: AppTheme.primaryGreen),
      title: const Text('Getting torrent info'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            peers > 0
                ? 'Connected to $peers peers, downloading the file list…'
                : known > 0
                ? 'Found $known peers, connecting…'
                : 'Looking for peers…',
            textAlign: TextAlign.center,
          ),
          if (waited > 45 && peers == 0) ...[
            const SizedBox(height: 10),
            const Text(
              'This is taking a while. Your network may block torrents; '
              'a VPN usually helps.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
