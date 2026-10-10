package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
)

// A torrent of one bare file (e.g. an ISO) lands as <saveDir>/<name>.
func TestSingleFileTorrent(t *testing.T) {
	tmp, err := os.MkdirTemp("", "torrentd-single-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(tmp) })
	seedRoot := filepath.Join(tmp, "seed")
	_ = os.MkdirAll(seedRoot, 0o755)
	data := make([]byte, 3<<20)
	_, _ = rand.Read(data)
	src := filepath.Join(seedRoot, "disc.iso")
	if err := os.WriteFile(src, data, 0o644); err != nil {
		t.Fatal(err)
	}
	info := metainfo.Info{PieceLength: 256 << 10}
	if err := info.BuildFromFilePath(src); err != nil {
		t.Fatal(err)
	}
	infoBytes, _ := bencode.Marshal(info)
	var raw bytes.Buffer
	_ = (&metainfo.MetaInfo{InfoBytes: infoBytes}).Write(&raw)
	_, peer := startSeeder(t, seedRoot, raw.Bytes())

	saveDir := filepath.Join(tmp, "games", "Disc")
	e, err := NewEngine(filepath.Join(tmp, "engine"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer e.Close()
	id, err := e.Add(AddRequest{TorrentB64: base64.StdEncoding.EncodeToString(raw.Bytes()), SaveDir: saveDir})
	if err != nil {
		t.Fatal(err)
	}
	if err := e.SelectFiles(id, []int{0}); err != nil {
		t.Fatal(err)
	}
	e.mu.Lock()
	e.items[id].t.AddPeers([]torrent.PeerInfo{peer})
	e.mu.Unlock()
	waitFor(t, "download", 60*time.Second, func() bool {
		st, _ := e.Get(id)
		return st.State == "completed" || st.State == "seeding"
	})
	st, _ := e.Get(id)
	if len(st.Files) != 1 || st.Files[0].Path != "disc.iso" {
		t.Fatalf("files = %+v", st.Files)
	}
	got, err := os.ReadFile(filepath.Join(saveDir, "disc.iso"))
	if err != nil || !bytes.Equal(got, data) {
		t.Fatalf("downloaded file mismatch: %v", err)
	}
	if err := e.Remove(id, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(saveDir, "disc.iso")); !os.IsNotExist(err) {
		t.Fatalf("file not deleted: %v", err)
	}
}
