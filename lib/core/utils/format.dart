/// Human-friendly file name for a mirror URL.
///
/// FitGirl mirror links carry the real name in the fragment
/// (`https://fuckingfast.co/abc#Game--fitgirl-repack.part01.rar`).
String fileNameFromUrl(String url) {
  final clean = url.trim();
  try {
    final uri = Uri.parse(clean);
    String name = uri.fragment;
    if (name.isEmpty && uri.pathSegments.isNotEmpty) {
      name = uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
    }
    if (name.isEmpty) name = clean;
    return Uri.decodeFull(name).replaceAll('\n', '').trim();
  } catch (_) {
    return clean.split('/').last;
  }
}

/// Makes a string safe to use as a file or folder name on every platform.
String sanitizeFileName(String name) => name
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(RegExp(r'[. ]+$'), '');

String formatBytes(num bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : decimals)} ${units[unit]}';
}

/// [mbPerSecond] as reported by background_downloader (MB/s).
String formatSpeed(double mbPerSecond) {
  if (mbPerSecond <= 0) return '0 KB/s';
  if (mbPerSecond < 1) return '${(mbPerSecond * 1024).toStringAsFixed(0)} KB/s';
  return '${mbPerSecond.toStringAsFixed(1)} MB/s';
}

String formatDuration(Duration? d) {
  if (d == null || d.inSeconds <= 0) return '--';
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  return '${d.inSeconds}s';
}

/// Parses scraped sizes such as "35.5 GB", "from 51.1 GB", "1,2 GB", "800 MB".
/// Returns bytes, or -1 if it cannot be parsed.
int parseSizeToBytes(String? text) {
  if (text == null) return -1;
  final match = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(TB|GB|MB|KB)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return -1;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? -1;
  if (value < 0) return -1;
  const mult = {'KB': 1024, 'MB': 1024 * 1024, 'GB': 1024 * 1024 * 1024};
  final unit = match.group(2)!.toUpperCase();
  final factor = unit == 'TB'
      ? 1024.0 * 1024 * 1024 * 1024
      : mult[unit]!.toDouble();
  return (value * factor).round();
}

String formatRelativeDate(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
