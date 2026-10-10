# torrentd

BitTorrent engine of FitGirl Downloader, built on
[anacrolix/torrent](https://github.com/anacrolix/torrent). The app starts it as
a child process and controls it over a token-protected JSON API on 127.0.0.1
(see `main.go` for the endpoints). It needs no cgo, so it cross-compiles
anywhere Go runs.

CI builds it into every release (see `.github/workflows/build_and_release.yml`).
To use torrents in a local `flutter run`, build it next to the app:

```bash
# Windows (after `flutter build windows` / `flutter run -d windows`)
go build -o ../../build/windows/x64/runner/Debug/torrentd.exe .

# Android (arm64 devices)
CGO_ENABLED=0 GOOS=android GOARCH=arm64 go build -trimpath \
  -ldflags="-s -w -checklinkname=0" \
  -o ../../android/app/src/main/jniLibs/arm64-v8a/libtorrentd.so .
```

Tests: `CGO_ENABLED=0 go test ./...` (offline swarm), and
`TORRENTD_BIN=/path/to/torrentd flutter test test/torrent_engine_test.dart`
drives the engine through the app's Dart client.
