# Fitgirl Downloader

**Fitgirl Downloader** is a modern, mobile-first application designed to make browsing and downloading FitGirl Repacks easier and more manageable. It features a sleek interface, selective file downloading, and powerful queue management.

## ✨ Features

- **Easy Browsing**: Latest and popular repacks, with infinite scroll and pull-to-refresh.
- **Smart Downloads**: Select *only* the files you need (e.g., skip optional language packs).
- **Real download manager**: Parallel downloads (configurable), per-file pause / resume / retry / "download next", queue ordering, and automatic retries with a fresh mirror link that resume from the partial file.
- **Change files any time**: Add or remove files from a running download — no need to pause first.
- **Notifications**: Progress notification on Android (keeps downloads alive in the background), and "game finished" / "file failed" alerts on every platform, including Windows, macOS and Linux.
- **Desktop-ready**: Sidebar navigation, master/detail downloads view, hover states, mouse-drag scrolling, keyboard shortcuts (Ctrl+1…5, Ctrl+F), "Open folder", and a sensible minimum window size.
- **Library**: Save your favorite games to your personal library.

## 📖 How to Use

### 1. Finding Games
- **Home Feed**: The main screen shows the latest repacks. Scroll down to automatically load more.
- **Search**: Use the search tab to find specific games. You can filter results to exclude "No Size" posts or trailers.

### 2. Downloading a Game
1.  Tap on any game to view its details (Description, Screenshots, etc.).
2.  Tap the **Download** button (Magnet icon).
3.  **Select Mirrors**: If multiple sources are available (Magnet, DataNodes, etc.), choose one.
4.  **Select Files**: You will see a list of all files in the repack.
    *   Uncheck files you don't need (like `optional-credits-video.bin` or language packs you won't use).
    *   Tap **Download Selected**.

### 3. Managing Downloads
Go to the **Downloads** tab to view your queue. On a wide window the list and the selected game's details are shown side by side.
- **Pause/Resume**: Per game, per file, or everything at once (Pause all / Resume all).
- **Add / remove files**: Open a download and choose **Add / remove files**. New files are queued immediately and removed files are cancelled; already downloaded files stay locked.
- **Failed files**: Files are retried automatically with a fresh link. After the retry limit they are marked *Failed* — use **Retry failed** to try again.
- **Queue order**: Use the ⋮ menu to move a game up/down, or "Download next" on a file.

### Settings
Download folder, number of parallel downloads, automatic retries, "one game at a time" mode and notifications are configurable in **Settings**. On desktop the default folder is your *Downloads* folder; each game goes to `FitGirl_Games/<game name>`.

### 4. Your Library
- Tap the **Heart** icon on any game detail page to add it to your Library.
- Access your saved games quickly from the **Library** tab.

## 🚀 Getting Started

### Installation
As this is a self-hosted project, you will need to build the app to install it on your device.

1.  **Clone the repository**
    ```bash
    git clone https://github.com/Sriharan-S/fitgirl-downloader.git
    cd fitgirl-downloader
    ```

2.  **Run the App**
    ```bash
    flutter run
    ```
    *Note: Connect your Android/iOS device via USB, or run `flutter run -d windows` (macos/linux) for the desktop app.*

## ⚠️ Disclaimer

**This application is a fan-made project and is NOT affiliated with, endorsed by, or connected to the FitGirl Repacks team.**

This tool is intended for educational purposes and to provide a better user interface for accessing publicly available content.
- The developer is not responsible for the content downloaded using this application.
- Please support game developers by purchasing the games you enjoy.
- Use this application responsibly and in accordance with your local laws and regulations.
