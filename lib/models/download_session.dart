class DownloadSession {
  final String gameTitle;
  final String coverUrl;
  final List<String> pendingUrls;
  final List<String> completedUrls; // List of original URLs that are done
  final List<String>
  activeTaskIds; // Task IDs currently running (should be 1 for sequential)
  final Map<String, double> fileProgress; // TaskID -> Progress (0.0 - 1.0)
  final int totalFiles;
  final double networkSpeed; // MB/s
  final double avgSpeed; // MB/s (Smoothed average)
  final double peakSpeed; // MB/s (Max recorded)
  final String currentFileName;
  final double currentFileProgress; // 0.0 - 1.0
  final bool isPaused;
  final String totalGameSize; // e.g. "35.5 GB"
  final List<String> originalUrls; // Full list of candidate files from scraping

  DownloadSession({
    required this.gameTitle,
    required this.coverUrl,
    required this.pendingUrls,
    required this.totalFiles,
    this.completedUrls = const [],
    this.activeTaskIds = const [],
    this.fileProgress = const {},
    this.networkSpeed = 0.0,
    this.avgSpeed = 0.0,
    this.peakSpeed = 0.0,
    this.currentFileName = '',
    this.currentFileProgress = 0.0,
    this.isPaused = false,
    this.totalGameSize = 'TBD',
    this.originalUrls = const [],
  });

  // Factory to create a new session
  factory DownloadSession.create({
    required String gameTitle,
    required String coverUrl,
    required List<String> urls,
    String totalGameSize = 'TBD',
    List<String> originalUrls = const [],
  }) {
    return DownloadSession(
      gameTitle: gameTitle,
      coverUrl: coverUrl,
      pendingUrls: urls,
      totalFiles: urls.length,
      totalGameSize: totalGameSize,
      originalUrls: originalUrls.isNotEmpty
          ? originalUrls
          : urls, // Fallback to initial selection if not provided
    );
  }

  // CopyWith for state updates
  DownloadSession copyWith({
    List<String>? pendingUrls,
    List<String>? completedUrls,
    List<String>? activeTaskIds,
    Map<String, double>? fileProgress,
    double? networkSpeed,
    double? avgSpeed,
    double? peakSpeed,
    String? currentFileName,
    double? currentFileProgress,
    bool? isPaused,
    String? totalGameSize,
    List<String>? originalUrls,
  }) {
    return DownloadSession(
      gameTitle: gameTitle,
      coverUrl: coverUrl,
      totalFiles: totalFiles,
      pendingUrls: pendingUrls ?? this.pendingUrls,
      completedUrls: completedUrls ?? this.completedUrls,
      activeTaskIds: activeTaskIds ?? this.activeTaskIds,
      fileProgress: fileProgress ?? this.fileProgress,
      networkSpeed: networkSpeed ?? this.networkSpeed,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      peakSpeed: peakSpeed ?? this.peakSpeed,
      currentFileName: currentFileName ?? this.currentFileName,
      currentFileProgress: currentFileProgress ?? this.currentFileProgress,
      isPaused: isPaused ?? this.isPaused,
      totalGameSize: totalGameSize ?? this.totalGameSize,
      originalUrls: originalUrls ?? this.originalUrls,
    );
  }

  // Progress Calculation
  double get overallProgress {
    if (totalFiles == 0) return 0.0;

    // Add 1.0 for every completed file
    double total = completedUrls.length.toDouble();

    // Add current progress of active files
    for (var taskId in activeTaskIds) {
      total += (fileProgress[taskId] ?? 0.0);
    }

    // Fallback: If currentFileProgress is set but map isn't (from service update)
    if (currentFileProgress > 0 && activeTaskIds.isNotEmpty) {
      if (fileProgress.isEmpty) {
        total += currentFileProgress;
      }
    }

    return total / totalFiles;
  }

  bool get isCompleted => completedUrls.length == totalFiles;

  // JSON Serialization for persistence
  Map<String, dynamic> toJson() {
    return {
      'gameTitle': gameTitle,
      'coverUrl': coverUrl,
      'pendingUrls': pendingUrls,
      'completedUrls': completedUrls,
      'activeTaskIds': activeTaskIds,
      'totalFiles': totalFiles,
      'totalGameSize': totalGameSize,
      'peakSpeed': peakSpeed, // Persist peak speed
      // We don't necessarily persist avgSpeed/networkSpeed as they are transient?
      // User requested "Restored upon app's reopen". So yes, persist them.
      'avgSpeed': avgSpeed,
      'originalUrls': originalUrls,
    };
  }

  factory DownloadSession.fromJson(Map<String, dynamic> json) {
    return DownloadSession(
      gameTitle: json['gameTitle'],
      coverUrl: json['coverUrl'],
      pendingUrls: List<String>.from(json['pendingUrls'] ?? []),
      completedUrls: List<String>.from(json['completedUrls'] ?? []),
      activeTaskIds: List<String>.from(json['activeTaskIds'] ?? []),
      totalFiles: json['totalFiles'] ?? 0,
      totalGameSize: json['totalGameSize'] ?? 'TBD',
      peakSpeed: (json['peakSpeed'] ?? 0.0).toDouble(),
      avgSpeed: (json['avgSpeed'] ?? 0.0).toDouble(),
      originalUrls: List<String>.from(json['originalUrls'] ?? []),
      fileProgress:
          {}, // Reset progress on load (unless we map it from active tasks)
    );
  }
}
