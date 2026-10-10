package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
)

// TestThroughput measures engine-to-engine speed over loopback, i.e. the
// engine's own ceiling (CPU, hashing, disk), without network limits.
// Run with: BENCH_MB=1024 go test -run Throughput -v
func TestThroughput(t *testing.T) {
	mb := 0
	fmt.Sscan(os.Getenv("BENCH_MB"), &mb)
	if mb == 0 {
		t.Skip("set BENCH_MB to run")
	}
	tmp, _ := os.MkdirTemp("", "torrentd-bench-")
	t.Cleanup(func() { _ = os.RemoveAll(tmp) })
	root := filepath.Join(tmp, "seed", "Big")
	_ = os.MkdirAll(root, 0o755)
	buf := make([]byte, 64<<20)
	for i := 0; i*64 < mb; i++ {
		_, _ = rand.Read(buf)
		_ = os.WriteFile(filepath.Join(root, fmt.Sprintf("fg-%02d.bin", i)), buf, 0o644)
	}
	info := metainfo.Info{PieceLength: 4 << 20}
	if err := info.BuildFromFilePath(root); err != nil {
		t.Fatal(err)
	}
	ib, _ := bencode.Marshal(info)
	var out bytes.Buffer
	_ = (&metainfo.MetaInfo{InfoBytes: ib}).Write(&out)
	b64 := base64.StdEncoding.EncodeToString(out.Bytes())

	seeder, _ := NewEngine(filepath.Join(tmp, "s"), 0)
	defer seeder.Close()
	seeder.SetSettings(Settings{Seed: true})
	id, _ := seeder.Add(AddRequest{TorrentB64: b64, SaveDir: root})
	st, _ := seeder.Get(id)
	var all []int
	for _, f := range st.Files {
		all = append(all, f.Index)
	}
	_ = seeder.SelectFiles(id, all)
	readyStart := time.Now()
	waitFor(t, "seeder ready", 5*time.Minute, func() bool {
		st, _ := seeder.Get(id)
		return st.State == "seeding"
	})
	t.Logf("seeder verified data in %.1fs", time.Since(readyStart).Seconds())

	leecher, _ := NewEngine(filepath.Join(tmp, "l"), 0)
	defer leecher.Close()
	_, _ = leecher.Add(AddRequest{TorrentB64: b64, SaveDir: filepath.Join(tmp, "dl")})
	_ = leecher.SelectFiles(id, all)
	start := time.Now()
	_ = leecher.AddPeers(id, []string{fmt.Sprintf("127.0.0.1:%d", seeder.PeerPort())})
	last := time.Now()
	waitFor(t, "download", 10*time.Minute, func() bool {
		st, _ := leecher.Get(id)
		if time.Since(last) > 5*time.Second {
			last = time.Now()
			t.Logf("t=%.0fs %d/%d MB rate=%.1f MB/s peers=%d", time.Since(start).Seconds(), st.BytesCompleted>>20, st.Length>>20, st.DownloadRate/(1<<20), st.Peers)
		}
		return st.State == "completed"
	})
	secs := time.Since(start).Seconds()
	t.Logf("RESULT %d MB in %.1fs = %.1f MB/s (single peer, loopback)", mb, secs, float64(mb)/secs)
}
