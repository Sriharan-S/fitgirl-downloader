/// Version of this build, injected by CI:
/// `--dart-define=APP_VERSION=v2026.10.11.42`. Local builds report "dev"
/// and never update themselves.
class AppVersion {
  static const String current = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static bool get isRelease => parse(current) != null;

  /// "v2026.10.11.42" -> [2026, 10, 11, 42]. Older date-only tags such as
  /// "v2026.10.10" parse too. Pre-release tags ("...-dev-abc1234") and
  /// anything else return null.
  static List<int>? parse(String tag) {
    final match = RegExp(r'^v?(\d+(?:\.\d+)*)$').firstMatch(tag.trim());
    if (match == null) return null;
    return match.group(1)!.split('.').map(int.parse).toList();
  }

  /// Negative when [a] is older than [b]. Missing parts count as 0.
  static int compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// Human-friendly form of a tag: "v2026.10.11.42" -> "2026.10.11 (build 42)".
  static String label(String tag) {
    final parts = parse(tag);
    if (parts == null) return tag;
    if (parts.length == 4) {
      return '${parts.take(3).join('.')} (build ${parts[3]})';
    }
    return parts.join('.');
  }
}
