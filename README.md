# Fitgirl Downloader

**Fitgirl Downloader** is a powerful, feature-rich mobile download manager designed specifically for FitGirl Repacks. Built with Flutter, it offers a sleek, "Cyberpunk"-inspired interface to browse games, manage selective downloads, and track progress with real-time analytics.

## ✨ Features

### 🎮 **Discovery & Browsing**
- **Automated Scraping**: Fetches the latest games directly from the FitGirl Repacks website.
- **Instant Search**: Powerful search with portrait thumbnails, strict filtering (excluding trailers/no-size posts), and search history.
- **Game Details**: View comprehensive game information, including covers, descriptions, and screenshots.
- **Incremental Loading**: Smooth, infinite scrolling for the discover page.

### ⬇️ **Smart Download Management**
- **Selective Downloading**: Choose exactly which files to download (e.g., specific language packs, optional files) to save data and space.
- **Pause & Select**: Uniquely allows you to pause an active download session, modify your file selection (add/remove files), and resume seamlessly.
- **Background Downloads**: Reliable background downloading with persistent notifications.
- **Mirrors Support**: Automatically extracts direct download links from supported mirrors (FuckingFast, DataNodes) and handles Pastebin redirects.
- **Queue System**: "Just-in-Time" scraper worker manages a sequential queue, resolving links only when needed to prevent expiration.

### 📊 **Analytics & library**
- **Real-time Stats**: Track download speed (current, peak, average) and ETA.
- **Library Management**: 'Favorites' system to save games for later.
- **Session Tracking**: Detailed view of active, queued, and completed downloads per game.

### 🎨 **Modern UI/UX**
- **Cyberpunk Aesthetic**: styled with a vibrant dark theme, glassmorphism effects, and fluid animations.
- **Responsive Design**: Optimized for mobile devices with intuitive navigation.

## 🛠️ Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Dart)
- **State Management**: [Riverpod](https://riverpod.dev/)
- **Routing**: [GoRouter](https://pub.dev/packages/go_router)
- **Networking**: `http`, `html` (parsing)
- **Downloading**: `background_downloader`
- **Persistence**: `shared_preferences`
- **UI Components**: `cached_network_image`, `shimmer`, `carousel_slider`, `lucide_icons`

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (Latest Stable)
- Android Studio / Xcode (for iOS)
- Git

### Installation

1.  **Clone the repository**
    ```bash
    git clone https://github.com/Sriharan-S/fitgirl-downloader.git
    cd fitgirl-downloader
    ```

2.  **Install Dependencies**
    ```bash
    flutter pub get
    ```

3.  **Run the App**
    ```bash
    flutter run
    ```

### Building for Release

**Android APK:**
```bash
flutter build apk --release
```

**Android App Bundle:**
```bash
flutter build appbundle --release
```

## ⚠️ Disclaimer

**This application is a fan-made project and is NOT affiliated with, endorsed by, or connected to the FitGirl Repacks team.**

This tool is intended for educational purposes and to provide a better user interface for accessing publicly available content.
- The developer is not responsible for the content downloaded using this application.
- Please support game developers by purchasing the games you enjoy.
- Use this application responsibly and in accordance with your local laws and regulations.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request
