import 'package:fitgirl_mobile_flutter/core/utils/format.dart';

/// Lifecycle of a single file inside a game download.
enum FileStatus {
  queued,
  resolving, // Fetching the direct link from the mirror page
  downloading,
  paused,
  completed,
  failed;

  bool get isActive => this == resolving || this == downloading;
  bool get isFinished => this == completed;

  static FileStatus fromName(String? name) => FileStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => FileStatus.queued,
  );
}

/// Aggregate status of a game download, derived from its files.
enum SessionStatus { downloading, queued, paused, failed, completed }

class DownloadFile {
  /// Mirror page URL (e.g. fuckingfast.co/xyz#file.part01.rar). Stable key.
  final String url;
  final String name;
  final FileStatus status;

  /// background_downloader task id for the current/last attempt.
  final String? taskId;
  final double progress; // 0.0 - 1.0
  final int expectedSize; // bytes, -1 when unknown
  final double speed; // MB/s (transient)
  final Duration? timeRemaining; // transient
  final String? error;
  final int attempts;

  /// The same file on other mirrors, tried when [url] fails.
  final List<String> alternates;

  const DownloadFile({
    required this.url,
    required this.name,
    this.status = FileStatus.queued,
    this.taskId,
    this.progress = 0.0,
    this.expectedSize = -1,
    this.speed = 0.0,
    this.timeRemaining,
    this.error,
    this.attempts = 0,
    this.alternates = const [],
  });

  factory DownloadFile.fromUrl(String url) =>
      DownloadFile(url: url, name: fileNameFromUrl(url));

  int get downloadedBytes {
    if (status == FileStatus.completed) {
      return expectedSize > 0 ? expectedSize : 0;
    }
    if (expectedSize <= 0) return 0;
    return (expectedSize * progress.clamp(0.0, 1.0)).round();
  }

  DownloadFile copyWith({
    FileStatus? status,
    String? taskId,
    bool clearTaskId = false,
    double? progress,
    int? expectedSize,
    double? speed,
    Duration? timeRemaining,
    bool clearTimeRemaining = false,
    String? error,
    bool clearError = false,
    int? attempts,
    List<String>? alternates,
  }) {
    return DownloadFile(
      url: url,
      name: name,
      status: status ?? this.status,
      taskId: clearTaskId ? null : (taskId ?? this.taskId),
      progress: progress ?? this.progress,
      expectedSize: expectedSize ?? this.expectedSize,
      speed: speed ?? this.speed,
      timeRemaining: clearTimeRemaining
          ? null
          : (timeRemaining ?? this.timeRemaining),
      error: clearError ? null : (error ?? this.error),
      attempts: attempts ?? this.attempts,
      alternates: alternates ?? this.alternates,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'status': status.name,
    'taskId': taskId,
    'progress': progress,
    'expectedSize': expectedSize,
    'error': error,
    'attempts': attempts,
    'alternates': alternates,
  };

  factory DownloadFile.fromJson(Map<String, dynamic> json) {
    final url = json['url'] as String;
    return DownloadFile(
      url: url,
      name: (json['name'] as String?) ?? fileNameFromUrl(url),
      status: FileStatus.fromName(json['status'] as String?),
      taskId: json['taskId'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      expectedSize: (json['expectedSize'] as num?)?.toInt() ?? -1,
      error: json['error'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      alternates: List<String>.from(json['alternates'] ?? const []),
    );
  }
}

/// Snapshot of a torrent's swarm, refreshed from the engine.
class TorrentInfo {
  final String infoHash;
  final String
  state; // metadata | waiting | downloading | paused | seeding | completed
  final int peers;
  final int seeders;
  final double downloadRate; // MB/s
  final double uploadRate; // MB/s

  const TorrentInfo({
    required this.infoHash,
    this.state = 'downloading',
    this.peers = 0,
    this.seeders = 0,
    this.downloadRate = 0,
    this.uploadRate = 0,
  });

  /// Pseudo URL identifying file [index] of a torrent; the fragment carries
  /// the path so names display and categorise like mirror links.
  static String fileUrl(String infoHash, int index, String path) =>
      'torrent:$infoHash/$index#$path';

  static int? fileIndex(String url) {
    final m = RegExp(r'^torrent:[0-9a-f]+/(\d+)').firstMatch(url);
    return m == null ? null : int.parse(m.group(1)!);
  }
}

class DownloadSession {
  final String gameTitle; // Unique key
  final String coverUrl;
  final String? gameUrl; // Source page, used to reopen details
  final String totalGameSize; // e.g. "from 35.5 GB" (as scraped)
  final List<DownloadFile> files; // Selected files, in download order
  final List<String> originalUrls; // Every file offered by the mirror
  final bool isPaused;
  final DateTime createdAt;
  final DateTime? completedAt;

  /// Set for downloads handled by the torrent engine.
  final TorrentInfo? torrent;

  // Transient stats
  final double avgSpeed; // MB/s
  final double peakSpeed; // MB/s

  bool get isTorrent => torrent != null;

  const DownloadSession({
    required this.gameTitle,
    required this.coverUrl,
    required this.files,
    required this.createdAt,
    this.gameUrl,
    this.totalGameSize = 'TBD',
    this.originalUrls = const [],
    this.isPaused = false,
    this.completedAt,
    this.avgSpeed = 0.0,
    this.peakSpeed = 0.0,
    this.torrent,
  });

  factory DownloadSession.create({
    required String gameTitle,
    required String coverUrl,
    required List<String> urls,
    Map<String, List<String>> alternates = const {},
    String? gameUrl,
    String totalGameSize = 'TBD',
    List<String> originalUrls = const [],
  }) {
    return DownloadSession(
      gameTitle: gameTitle,
      coverUrl: coverUrl,
      gameUrl: gameUrl,
      files: [
        for (final u in urls)
          DownloadFile.fromUrl(u).copyWith(alternates: alternates[u]),
      ],
      totalGameSize: totalGameSize,
      originalUrls: originalUrls.isNotEmpty ? originalUrls : urls,
      createdAt: DateTime.now(),
    );
  }

  DownloadSession copyWith({
    List<DownloadFile>? files,
    List<String>? originalUrls,
    bool? isPaused,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    double? avgSpeed,
    double? peakSpeed,
    TorrentInfo? torrent,
  }) {
    return DownloadSession(
      gameTitle: gameTitle,
      coverUrl: coverUrl,
      gameUrl: gameUrl,
      totalGameSize: totalGameSize,
      createdAt: createdAt,
      files: files ?? this.files,
      originalUrls: originalUrls ?? this.originalUrls,
      isPaused: isPaused ?? this.isPaused,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      avgSpeed: avgSpeed ?? this.avgSpeed,
      peakSpeed: peakSpeed ?? this.peakSpeed,
      torrent: torrent ?? this.torrent,
    );
  }

  // ---------------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------------

  int get totalFiles => files.length;
  int countWhere(FileStatus s) => files.where((f) => f.status == s).length;
  int get completedCount => countWhere(FileStatus.completed);
  int get failedCount => countWhere(FileStatus.failed);
  int get activeCount => files.where((f) => f.status.isActive).length;
  int get queuedCount => countWhere(FileStatus.queued);

  List<String> get selectedUrls => files.map((f) => f.url).toList();
  List<String> get completedUrls => files
      .where((f) => f.status == FileStatus.completed)
      .map((f) => f.url)
      .toList();

  bool get isCompleted =>
      files.isNotEmpty && files.every((f) => f.status == FileStatus.completed);

  /// Files the user still expects to finish (not completed, not failed).
  bool get hasRemainingWork => files.any(
    (f) => f.status != FileStatus.completed && f.status != FileStatus.failed,
  );

  SessionStatus get status {
    if (isCompleted) return SessionStatus.completed;
    if (isPaused) return SessionStatus.paused;
    if (activeCount > 0) return SessionStatus.downloading;
    if (!hasRemainingWork && failedCount > 0) return SessionStatus.failed;
    return SessionStatus.queued;
  }

  double get networkSpeed => isTorrent
      ? (status == SessionStatus.downloading ? torrent!.downloadRate : 0)
      : files
            .where((f) => f.status == FileStatus.downloading)
            .fold(0.0, (sum, f) => sum + f.speed);

  /// Byte-accurate progress when sizes are known, file-count based otherwise.
  double get overallProgress {
    if (files.isEmpty) return 0.0;
    double total = 0;
    for (final f in files) {
      total += f.status == FileStatus.completed ? 1.0 : f.progress.clamp(0, 1);
    }
    return (total / files.length).clamp(0.0, 1.0);
  }

  int get downloadedBytes => files.fold(0, (s, f) => s + f.downloadedBytes);

  /// Estimated total bytes of the selection. Uses known sizes and fills unknown
  /// ones with the average known size (FitGirl parts are usually equal).
  int get estimatedTotalBytes {
    final known = files.where((f) => f.expectedSize > 0).toList();
    if (known.isEmpty) return -1;
    final avg = known.fold<int>(0, (s, f) => s + f.expectedSize) / known.length;
    return files.fold<int>(
      0,
      (s, f) => s + (f.expectedSize > 0 ? f.expectedSize : avg.round()),
    );
  }

  Duration? get eta {
    final speed = networkSpeed;
    final total = estimatedTotalBytes;
    if (speed <= 0 || total <= 0) return null;
    final remaining = total - downloadedBytes;
    if (remaining <= 0) return null;
    return Duration(seconds: (remaining / (speed * 1024 * 1024)).round());
  }

  DownloadFile? fileForTask(String taskId) {
    for (final f in files) {
      if (f.taskId == taskId) return f;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'version': 2,
    'gameTitle': gameTitle,
    'coverUrl': coverUrl,
    'gameUrl': gameUrl,
    'totalGameSize': totalGameSize,
    'files': files.map((f) => f.toJson()).toList(),
    'originalUrls': originalUrls,
    'isPaused': isPaused,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'avgSpeed': avgSpeed,
    'peakSpeed': peakSpeed,
    if (torrent != null) 'torrentInfoHash': torrent!.infoHash,
  };

  factory DownloadSession.fromJson(Map<String, dynamic> json) {
    List<DownloadFile> files;
    if (json['files'] is List) {
      files = (json['files'] as List)
          .map((e) => DownloadFile.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      // Legacy (v1) format: pendingUrls / completedUrls / activeTaskIds.
      // Active task URLs were only stored in task metadata, so anything that
      // was in flight is re-queued; the service reconciles it on startup.
      final completed = List<String>.from(json['completedUrls'] ?? []);
      final pending = List<String>.from(json['pendingUrls'] ?? []);
      final original = List<String>.from(json['originalUrls'] ?? []);
      final known = {...completed, ...pending};
      files = [
        ...completed.map(
          (u) => DownloadFile.fromUrl(
            u,
          ).copyWith(status: FileStatus.completed, progress: 1.0),
        ),
        ...pending.map(DownloadFile.fromUrl),
      ];
      // Legacy sessions tracked totalFiles; recover in-flight files that were
      // neither pending nor completed from the original list.
      final legacyTotal = (json['totalFiles'] as num?)?.toInt() ?? 0;
      if (files.length < legacyTotal) {
        for (final u in original) {
          if (files.length >= legacyTotal) break;
          if (!known.contains(u)) {
            files.insert(completed.length, DownloadFile.fromUrl(u));
          }
        }
      }
    }

    return DownloadSession(
      gameTitle: json['gameTitle'] as String,
      coverUrl: (json['coverUrl'] as String?) ?? '',
      gameUrl: json['gameUrl'] as String?,
      totalGameSize: (json['totalGameSize'] as String?) ?? 'TBD',
      files: files,
      originalUrls: List<String>.from(json['originalUrls'] ?? []),
      isPaused: (json['isPaused'] as bool?) ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      avgSpeed: (json['avgSpeed'] as num?)?.toDouble() ?? 0.0,
      peakSpeed: (json['peakSpeed'] as num?)?.toDouble() ?? 0.0,
      torrent: json['torrentInfoHash'] is String
          ? TorrentInfo(
              infoHash: json['torrentInfoHash'] as String,
              state: 'paused',
            )
          : null,
    );
  }
}
