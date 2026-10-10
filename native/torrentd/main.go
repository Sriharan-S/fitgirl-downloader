// torrentd is the BitTorrent engine of FitGirl Downloader.
//
// The app starts it as a child process and controls it through a small JSON
// API on 127.0.0.1. Every request must carry the token passed with -token.
// When the app exits (its end of stdin closes) the engine saves its state and
// exits too.
//
//	POST   /torrents                 {magnet|torrentUrl|torrentBase64, saveDir} -> {infoHash}
//	GET    /torrents                 -> [status]          (?files=1 for file lists)
//	GET    /torrents/{id}            -> status with files
//	POST   /torrents/{id}/files      {selected:[index...]}
//	POST   /torrents/{id}/peers      {peers:["host:port"...]}
//	POST   /torrents/{id}/pause
//	POST   /torrents/{id}/resume
//	DELETE /torrents/{id}            (?deleteFiles=1)
//	POST   /settings                 {seed}
//	GET    /health
package main

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"github.com/anacrolix/torrent/bencode"
	"github.com/anacrolix/torrent/metainfo"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
)

var version = "dev"

func main() {
	// torrentd mktorrent DIR OUT.torrent: creates a torrent (used by tests).
	if len(os.Args) == 4 && os.Args[1] == "mktorrent" {
		if err := makeTorrent(os.Args[2], os.Args[3]); err != nil {
			log.Fatal(err)
		}
		return
	}

	dataDir := flag.String("data", "", "directory for engine state")
	token := flag.String("token", "", "API token required on every request")
	apiPort := flag.Int("port", 0, "API port on 127.0.0.1 (0 = random)")
	peerPort := flag.Int("peer-port", 0, "BitTorrent listen port (0 = random)")
	watchStdin := flag.Bool("watch-stdin", true, "exit when stdin is closed")
	flag.Parse()
	if *dataDir == "" || *token == "" {
		fmt.Fprintln(os.Stderr, "usage: torrentd -data DIR -token TOKEN")
		os.Exit(2)
	}

	engine, err := NewEngine(*dataDir, *peerPort)
	if err != nil {
		log.Fatal(err)
	}

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", *apiPort))
	if err != nil {
		log.Fatal(err)
	}
	srv := &http.Server{Handler: newAPI(engine, *token)}
	go func() { _ = srv.Serve(ln) }()

	// The app reads this line to learn the port.
	fmt.Printf("READY %d\n", ln.Addr().(*net.TCPAddr).Port)

	done := make(chan struct{})
	if *watchStdin {
		go func() {
			_, _ = io.Copy(io.Discard, os.Stdin)
			close(done)
		}()
	}
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	select {
	case <-done:
	case <-sig:
	}
	_ = srv.Close()
	engine.Close()
}

func newAPI(e *Engine, token string) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]any{"ok": true, "version": version, "peerPort": e.PeerPort()})
	})
	mux.HandleFunc("POST /torrents", func(w http.ResponseWriter, r *http.Request) {
		var req AddRequest
		if !readJSON(w, r, &req) {
			return
		}
		id, err := e.Add(req)
		if err != nil {
			writeErr(w, err)
			return
		}
		writeJSON(w, map[string]string{"infoHash": id})
	})
	mux.HandleFunc("GET /torrents", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, e.List(r.URL.Query().Get("files") == "1"))
	})
	mux.HandleFunc("GET /torrents/{id}", func(w http.ResponseWriter, r *http.Request) {
		st, err := e.Get(r.PathValue("id"))
		if err != nil {
			writeErr(w, err)
			return
		}
		writeJSON(w, st)
	})
	mux.HandleFunc("POST /torrents/{id}/files", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Selected []int `json:"selected"`
		}
		if !readJSON(w, r, &req) {
			return
		}
		respond(w, e.SelectFiles(r.PathValue("id"), req.Selected))
	})
	mux.HandleFunc("POST /torrents/{id}/peers", func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Peers []string `json:"peers"`
		}
		if !readJSON(w, r, &req) {
			return
		}
		respond(w, e.AddPeers(r.PathValue("id"), req.Peers))
	})
	mux.HandleFunc("POST /torrents/{id}/pause", func(w http.ResponseWriter, r *http.Request) {
		respond(w, e.SetPaused(r.PathValue("id"), true))
	})
	mux.HandleFunc("POST /torrents/{id}/resume", func(w http.ResponseWriter, r *http.Request) {
		respond(w, e.SetPaused(r.PathValue("id"), false))
	})
	mux.HandleFunc("DELETE /torrents/{id}", func(w http.ResponseWriter, r *http.Request) {
		respond(w, e.Remove(r.PathValue("id"), r.URL.Query().Get("deleteFiles") == "1"))
	})
	mux.HandleFunc("POST /settings", func(w http.ResponseWriter, r *http.Request) {
		var s Settings
		if !readJSON(w, r, &s) {
			return
		}
		e.SetSettings(s)
		respond(w, nil)
	})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Token")), []byte(token)) != 1 {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		mux.ServeHTTP(w, r)
	})
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	dec := json.NewDecoder(io.LimitReader(r.Body, 25<<20))
	if err := dec.Decode(v); err != nil && !errors.Is(err, io.EOF) {
		http.Error(w, "bad request: "+err.Error(), http.StatusBadRequest)
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, err error) {
	status := http.StatusBadRequest
	if errors.Is(err, errNotFound) {
		status = http.StatusNotFound
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": strings.TrimSpace(err.Error())})
}

func respond(w http.ResponseWriter, err error) {
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func makeTorrent(dir, out string) error {
	info := metainfo.Info{PieceLength: 256 << 10}
	if err := info.BuildFromFilePath(dir); err != nil {
		return err
	}
	infoBytes, err := bencode.Marshal(info)
	if err != nil {
		return err
	}
	f, err := os.Create(out)
	if err != nil {
		return err
	}
	defer f.Close()
	return (&metainfo.MetaInfo{InfoBytes: infoBytes}).Write(f)
}
