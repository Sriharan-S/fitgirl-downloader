package main

import (
	"encoding/base64"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// An engine must recognise complete data already on disk and seed it to
// another engine (regression: with the client's Seed=false, finished
// torrents refused every incoming peer).
func TestEngineSeedsExistingDataToAnotherEngine(t *testing.T) {
	tmp, err := os.MkdirTemp("", "torrentd-pair-")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(tmp) })
	seedRoot := filepath.Join(tmp, "seed")
	b64 := base64.StdEncoding.EncodeToString(makeRepack(t, seedRoot))

	seeder, err := NewEngine(filepath.Join(tmp, "s"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer seeder.Close()
	seeder.SetSettings(Settings{Seed: true})
	id, err := seeder.Add(AddRequest{TorrentB64: b64, SaveDir: filepath.Join(seedRoot, "Game [FitGirl Repack]")})
	if err != nil {
		t.Fatal(err)
	}
	st, _ := seeder.Get(id)
	var all []int
	for _, f := range st.Files {
		all = append(all, f.Index)
	}
	if err := seeder.SelectFiles(id, all); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "existing data recognised", 15*time.Second, func() bool {
		st, _ := seeder.Get(id)
		return st.State == "seeding"
	})

	leecher, err := NewEngine(filepath.Join(tmp, "l"), 0)
	if err != nil {
		t.Fatal(err)
	}
	defer leecher.Close()
	if _, err := leecher.Add(AddRequest{TorrentB64: b64, SaveDir: filepath.Join(tmp, "dl")}); err != nil {
		t.Fatal(err)
	}
	if err := leecher.SelectFiles(id, all); err != nil {
		t.Fatal(err)
	}
	if err := leecher.AddPeers(id, []string{fmt.Sprintf("127.0.0.1:%d", seeder.PeerPort())}); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "download from engine seeder", 60*time.Second, func() bool {
		st, _ := leecher.Get(id)
		return st.State == "completed"
	})
}
