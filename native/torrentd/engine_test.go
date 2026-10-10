package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
)

// Offline swarm: no DHT, trackers or internet; peers are added by hand.
func init() {
	configHook = func(cfg *torrent.ClientConfig) {
		cfg.NoDHT = true
		cfg.DisableTrackers = true
		cfg.DisableIPv6 = true
		cfg.ListenHost = func(string) string { return "127.0.0.1" }
	}
}

// makeRepack writes a FitGirl-like multi-file torrent and returns its
// metainfo bytes.
func makeRepack(t *testing.T, dir string) []byte {
	t.Helper()
	root := filepath.Join(dir, "Game [FitGirl Repack]")
	files := map[string]int{
		"setup.exe":                     300 << 10,
		"fg-01.bin":                     3 << 20,
		"fg-02.bin":                     3 << 20,
		"fg-selective-french.bin":       2 << 20,
		"fg-optional-bonus-content.bin": 1 << 20,
	}
	for name, size := range files {
		buf := make([]byte, size)
		_, _ = rand.Read(buf)
		if err := os.MkdirAll(root, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, name), buf, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	info := metainfo.Info{PieceLength: 256 << 10}
	if err := info.BuildFromFilePath(root); err != nil {
		t.Fatal(err)
	}
	infoBytes, err := bencode.Marshal(info)
	if err != nil {
		t.Fatal(err)
	}
	mi := metainfo.MetaInfo{InfoBytes: infoBytes}
	var buf bytes.Buffer
	if err := mi.Write(&buf); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func startSeeder(t *testing.T, dataRoot string, raw []byte) (*torrent.Client, torrent.PeerInfo) {
	t.Helper()
	cfg := torrent.NewDefaultClientConfig()
	configHook(cfg)
	cfg.DataDir = dataRoot
	cfg.Seed = true
	cfg.ListenPort = 0
	cl, err := torrent.NewClient(cfg)
	if err != nil {
		t.Fatal(err)
	}
	mi, _ := metainfo.Load(bytes.NewReader(raw))
	tor, err := cl.AddTorrent(mi)
	if err != nil {
		t.Fatal(err)
	}
	<-tor.GotInfo()
	tor.VerifyData()
	t.Cleanup(func() { cl.Close() })
	waitFor(t, "seeder verification", 30*time.Second, func() bool {
		return tor.Complete().Bool()
	})
	addr := cl.ListenAddrs()[0].(*net.TCPAddr)
	return cl, torrent.PeerInfo{Addr: addr, Trusted: true}
}

func waitFor(t *testing.T, what string, timeout time.Duration, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestSelectiveDownloadPauseResumeAndRestart(t *testing.T) {
	// Not t.TempDir(): on Windows the seeder may still hold file handles
	// when the test ends, which would fail the automatic cleanup.
	tmp, err := os.MkdirTemp("", "torrentd-test-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(tmp) })
	seedRoot := filepath.Join(tmp, "seed")
	raw := makeRepack(t, seedRoot)
	_, peer := startSeeder(t, seedRoot, raw)

	dataDir := filepath.Join(tmp, "engine")
	saveDir := filepath.Join(tmp, "games", "Game")
	e, err := NewEngine(dataDir, 0)
	if err != nil {
		t.Fatal(err)
	}
	id, err := e.Add(AddRequest{TorrentB64: base64.StdEncoding.EncodeToString(raw), SaveDir: saveDir})
	if err != nil {
		t.Fatal(err)
	}
	addPeer := func(e *Engine) {
		e.mu.Lock()
		e.items[id].t.AddPeers([]torrent.PeerInfo{peer})
		e.mu.Unlock()
	}
	addPeer(e)

	// Metadata known, nothing selected yet -> waiting, nothing downloaded.
	waitFor(t, "metadata", 10*time.Second, func() bool {
		st, _ := e.Get(id)
		return st.HasMetadata
	})
	st, _ := e.Get(id)
	if st.State != "waiting" || len(st.Files) != 5 {
		t.Fatalf("want waiting with 5 files, got %s with %d", st.State, len(st.Files))
	}

	// Select everything except the French and bonus packs.
	var selected, skipped []FileStatus
	var indexes []int
	for _, f := range st.Files {
		if bytes.Contains([]byte(f.Path), []byte("selective")) || bytes.Contains([]byte(f.Path), []byte("optional")) {
			skipped = append(skipped, f)
		} else {
			selected = append(selected, f)
			indexes = append(indexes, f.Index)
		}
	}
	if err := e.SelectFiles(id, indexes); err != nil {
		t.Fatal(err)
	}

	// Pause right away, check that it holds, then resume.
	if err := e.SetPaused(id, true); err != nil {
		t.Fatal(err)
	}
	time.Sleep(1500 * time.Millisecond)
	if st, _ := e.Get(id); st.State != "paused" {
		t.Fatalf("want paused, got %s", st.State)
	}
	if err := e.SetPaused(id, false); err != nil {
		t.Fatal(err)
	}

	waitFor(t, "selected files", 60*time.Second, func() bool {
		st, _ := e.Get(id)
		return st.State == "completed"
	})

	// Selected files are on disk with the seeder's exact content, directly
	// inside the save folder; skipped ones were not downloaded.
	for _, f := range selected {
		want, _ := os.ReadFile(filepath.Join(seedRoot, "Game [FitGirl Repack]", f.Path))
		got, err := os.ReadFile(filepath.Join(saveDir, f.Path))
		if err != nil || !bytes.Equal(want, got) {
			t.Fatalf("%s: content mismatch (err=%v)", f.Path, err)
		}
	}
	st, _ = e.Get(id)
	for _, f := range st.Files {
		for _, s := range skipped {
			if f.Index == s.Index && f.BytesCompleted == f.Length {
				t.Fatalf("%s should not have been downloaded", f.Path)
			}
		}
	}

	// Restart: the torrent, its selection and its progress come back.
	e.Close()
	e2, err := NewEngine(dataDir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer e2.Close()
	waitFor(t, "restored torrent", 15*time.Second, func() bool {
		st, err := e2.Get(id)
		return err == nil && st.State == "completed"
	})

	// Add the French pack later: only it is fetched.
	addPeer(e2)
	if err := e2.SelectFiles(id, append(indexes, skipped[0].Index)); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "added file", 60*time.Second, func() bool {
		st, _ := e2.Get(id)
		return st.State == "completed"
	})

	// Remove with files deleted.
	if err := e2.Remove(id, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(saveDir, selected[0].Path)); !os.IsNotExist(err) {
		t.Fatalf("expected files to be deleted, stat err=%v", err)
	}
	if len(e2.List(false)) != 0 {
		t.Fatal("torrent still listed after removal")
	}
}

func TestMagnetWithoutPeersWaitsForMetadata(t *testing.T) {
	e, err := NewEngine(t.TempDir(), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer e.Close()
	id, err := e.Add(AddRequest{
		Magnet:  "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test",
		SaveDir: t.TempDir(),
	})
	if err != nil {
		t.Fatal(err)
	}
	st, err := e.Get(id)
	if err != nil || st.State != "metadata" || st.HasMetadata {
		t.Fatalf("want metadata state, got %+v err=%v", st, err)
	}
}
