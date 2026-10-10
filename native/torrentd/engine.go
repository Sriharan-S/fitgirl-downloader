package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	alog "github.com/anacrolix/log"
	"github.com/anacrolix/torrent"
	"github.com/anacrolix/torrent/metainfo"
	"github.com/anacrolix/torrent/storage"
	"golang.org/x/time/rate"
)

// Engine owns the BitTorrent client and the list of torrents the app added.
// Everything it needs to restore after a restart is kept in session.json.
type Engine struct {
	mu        sync.Mutex
	client    *torrent.Client
	dataDir   string
	stateFile string
	seed      bool
	maxConns  int
	items     map[string]*item // key: info hash (hex)
	stop      chan struct{}
}

type item struct {
	t        *torrent.Torrent
	saved    savedTorrent
	rateDown float64 // bytes/s
	rateUp   float64
	lastDown int64
	lastUp   int64
	lastAt   time.Time
}

// savedTorrent is the persisted form of a torrent.
type savedTorrent struct {
	InfoHash    string `json:"infoHash"`
	Magnet      string `json:"magnet,omitempty"`
	MetaInfoB64 string `json:"metaInfo,omitempty"` // Raw .torrent once known
	SaveDir     string `json:"saveDir"`
	Selected    []int  `json:"selected"` // nil = nothing chosen yet
	Paused      bool   `json:"paused"`
	AddedAt     int64  `json:"addedAt"`
}

type Settings struct {
	Seed bool `json:"seed"`
}

// configHook lets tests adjust the client config (e.g. disable DHT).
var configHook func(*torrent.ClientConfig)

func NewEngine(dataDir string, listenPort int) (*Engine, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, err
	}
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = dataDir
	cfg.ListenPort = listenPort
	// Seeding is decided per torrent in tick(); with Seed=false the client
	// would refuse every incoming peer for finished torrents, so the
	// "seed after download" setting could never take effect.
	cfg.Seed = true
	cfg.Logger = cfg.Logger.WithFilterLevel(alog.Warning)
	cfg.Slogger = slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))
	// Library defaults are conservative (50 connections per torrent, 10 new
	// connections per second, 25 dials at once, 2 hashing goroutines).
	// FitGirl torrents have big swarms; these values are closer to
	// qBittorrent's and let the engine find and keep fast peers.
	cfg.EstablishedConnsPerTorrent = 100
	cfg.HalfOpenConnsPerTorrent = 50
	cfg.TotalHalfOpenConns = 200
	cfg.TorrentPeersHighWater = 1000
	cfg.DialRateLimiter = rate.NewLimiter(40, 40)
	cfg.PieceHashersPerTorrent = 4
	if configHook != nil {
		configHook(cfg)
	}
	client, err := torrent.NewClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("starting torrent client: %w", err)
	}
	e := &Engine{
		maxConns:  cfg.EstablishedConnsPerTorrent,
		client:    client,
		dataDir:   dataDir,
		stateFile: filepath.Join(dataDir, "session.json"),
		items:     map[string]*item{},
		stop:      make(chan struct{}),
	}
	e.restore()
	go e.tick()
	return e, nil
}

func (e *Engine) Close() {
	close(e.stop)
	e.mu.Lock()
	e.saveLocked()
	e.mu.Unlock()
	e.client.Close()
}

// ---------------------------------------------------------------------------
// Adding torrents
// ---------------------------------------------------------------------------

type AddRequest struct {
	Magnet     string `json:"magnet"`
	TorrentURL string `json:"torrentUrl"`
	TorrentB64 string `json:"torrentBase64"`
	SaveDir    string `json:"saveDir"`
}

func (e *Engine) Add(req AddRequest) (string, error) {
	if req.SaveDir == "" {
		return "", errors.New("saveDir is required")
	}
	saved := savedTorrent{SaveDir: req.SaveDir, AddedAt: time.Now().Unix()}
	switch {
	case req.Magnet != "":
		saved.Magnet = req.Magnet
	case req.TorrentB64 != "":
		saved.MetaInfoB64 = req.TorrentB64
	case req.TorrentURL != "":
		raw, err := fetchTorrentFile(req.TorrentURL)
		if err != nil {
			return "", err
		}
		saved.MetaInfoB64 = base64.StdEncoding.EncodeToString(raw)
	default:
		return "", errors.New("magnet, torrentUrl or torrentBase64 is required")
	}

	e.mu.Lock()
	defer e.mu.Unlock()
	it, err := e.addLocked(saved)
	if err != nil {
		return "", err
	}
	e.saveLocked()
	return it.saved.InfoHash, nil
}

func fetchTorrentFile(url string) ([]byte, error) {
	client := &http.Client{Timeout: 60 * time.Second}
	req, _ := http.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36")
	res, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("downloading .torrent: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("downloading .torrent: HTTP %d", res.StatusCode)
	}
	return io.ReadAll(io.LimitReader(res.Body, 20<<20))
}

func (e *Engine) addLocked(saved savedTorrent) (*item, error) {
	var spec *torrent.TorrentSpec
	var err error
	if saved.MetaInfoB64 != "" {
		raw, decErr := base64.StdEncoding.DecodeString(saved.MetaInfoB64)
		if decErr != nil {
			return nil, fmt.Errorf("bad torrent data: %w", decErr)
		}
		mi, loadErr := metainfo.Load(bytes.NewReader(raw))
		if loadErr != nil {
			return nil, fmt.Errorf("bad torrent file: %w", loadErr)
		}
		spec, err = torrent.TorrentSpecFromMetaInfoErr(mi)
	} else {
		spec, err = torrent.TorrentSpecFromMagnetUri(saved.Magnet)
	}
	if err != nil {
		return nil, err
	}

	// Files go straight into the game folder (no extra torrent-name folder).
	spec.Storage = storage.NewFileOpts(storage.NewFileClientOpts{
		ClientBaseDir: saved.SaveDir,
		TorrentDirMaker: func(baseDir string, _ *metainfo.Info, _ metainfo.Hash) string {
			return baseDir
		},
		FilePathMaker: func(opts storage.FilePathMakerOpts) string {
			return filepath.Join(opts.File.BestPath()...)
		},
	})

	key := spec.InfoHash.HexString()
	if existing, ok := e.items[key]; ok {
		return existing, nil
	}
	t, _, err := e.client.AddTorrentSpec(spec)
	if err != nil {
		return nil, err
	}
	saved.InfoHash = key
	it := &item{t: t, saved: saved, lastAt: time.Now()}
	e.items[key] = it

	// Nothing downloads until the user picks files (or a selection was
	// restored); metadata is fetched regardless.
	go func() {
		select {
		case <-t.GotInfo():
		case <-e.stop:
			return
		}
		e.mu.Lock()
		defer e.mu.Unlock()
		if it.saved.MetaInfoB64 == "" {
			var buf bytes.Buffer
			mi := t.Metainfo()
			if err := mi.Write(&buf); err == nil {
				it.saved.MetaInfoB64 = base64.StdEncoding.EncodeToString(buf.Bytes())
				e.saveLocked()
			}
		}
		e.applyLocked(it)
	}()
	return it, nil
}

// applyLocked pushes the saved selection and pause state into the client.
func (e *Engine) applyLocked(it *item) {
	t := it.t
	if t.Info() == nil {
		return
	}
	selected := map[int]bool{}
	for _, i := range it.saved.Selected {
		selected[i] = true
	}
	for i, f := range t.Files() {
		if selected[i] && !it.saved.Paused {
			f.SetPriority(torrent.PiecePriorityNormal)
		} else {
			f.SetPriority(torrent.PiecePriorityNone)
		}
	}
	if it.saved.Paused || it.saved.Selected == nil {
		t.DisallowDataDownload()
	} else {
		t.AllowDataDownload()
	}
	if it.saved.Paused {
		t.DisallowDataUpload()
	} else {
		t.AllowDataUpload()
	}
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

var errNotFound = errors.New("torrent not found")

func (e *Engine) withItem(id string, fn func(it *item) error) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	it, ok := e.items[id]
	if !ok {
		return errNotFound
	}
	if err := fn(it); err != nil {
		return err
	}
	e.applyLocked(it)
	e.saveLocked()
	return nil
}

func (e *Engine) SelectFiles(id string, indexes []int) error {
	return e.withItem(id, func(it *item) error {
		if indexes == nil {
			indexes = []int{}
		}
		it.saved.Selected = indexes
		return nil
	})
}

func (e *Engine) SetPaused(id string, paused bool) error {
	return e.withItem(id, func(it *item) error {
		it.saved.Paused = paused
		return nil
	})
}

func (e *Engine) Remove(id string, deleteFiles bool) error {
	e.mu.Lock()
	it, ok := e.items[id]
	if !ok {
		e.mu.Unlock()
		return errNotFound
	}
	var paths []string
	if deleteFiles && it.t.Info() != nil {
		for _, f := range it.t.Files() {
			p := filepath.Join(it.saved.SaveDir, filepath.FromSlash(f.DisplayPath()))
			paths = append(paths, p, p+".part")
		}
	}
	t := it.t
	t.Drop()
	delete(e.items, id)
	e.saveLocked()
	e.mu.Unlock()
	if len(paths) == 0 {
		return nil
	}
	// Storage closes its file handles asynchronously; Windows refuses to
	// delete files that are still open.
	select {
	case <-t.Closed():
	case <-time.After(10 * time.Second):
	}
	var lastErr error
	for attempt := 0; attempt < 20; attempt++ {
		lastErr = nil
		for _, p := range paths {
			if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
				lastErr = err
			}
		}
		if lastErr == nil {
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	return fmt.Errorf("removed torrent but could not delete all files: %w", lastErr)
}

// AddPeers connects a torrent to peers given as "host:port".
func (e *Engine) AddPeers(id string, addrs []string) error {
	e.mu.Lock()
	defer e.mu.Unlock()
	it, ok := e.items[id]
	if !ok {
		return errNotFound
	}
	var peers []torrent.PeerInfo
	for _, a := range addrs {
		addr, err := net.ResolveTCPAddr("tcp", a)
		if err != nil {
			return fmt.Errorf("bad peer address %q: %w", a, err)
		}
		peers = append(peers, torrent.PeerInfo{Addr: addr, Trusted: true})
	}
	it.t.AddPeers(peers)
	return nil
}

// PeerPort is the port other BitTorrent clients connect to.
func (e *Engine) PeerPort() int { return e.client.LocalPort() }

func (e *Engine) SetSettings(s Settings) {
	e.mu.Lock()
	e.seed = s.Seed
	e.mu.Unlock()
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

type FileStatus struct {
	Index          int    `json:"index"`
	Path           string `json:"path"`
	Length         int64  `json:"length"`
	BytesCompleted int64  `json:"bytesCompleted"`
	Selected       bool   `json:"selected"`
}

type TorrentStatus struct {
	InfoHash       string       `json:"infoHash"`
	Name           string       `json:"name"`
	SaveDir        string       `json:"saveDir"`
	HasMetadata    bool         `json:"hasMetadata"`
	State          string       `json:"state"`          // metadata | waiting | downloading | paused | seeding | completed
	Length         int64        `json:"length"`         // selected files
	BytesCompleted int64        `json:"bytesCompleted"` // selected files
	DownloadRate   float64      `json:"downloadRate"`   // bytes/s
	UploadRate     float64      `json:"uploadRate"`
	Peers          int          `json:"peers"`
	Seeders        int          `json:"seeders"`
	KnownPeers     int          `json:"knownPeers"`
	Files          []FileStatus `json:"files,omitempty"`
	AddedAt        int64        `json:"addedAt"`
}

func (e *Engine) statusLocked(it *item, withFiles bool) TorrentStatus {
	t := it.t
	st := TorrentStatus{
		InfoHash:     it.saved.InfoHash,
		Name:         t.Name(),
		SaveDir:      it.saved.SaveDir,
		HasMetadata:  t.Info() != nil,
		DownloadRate: it.rateDown,
		UploadRate:   it.rateUp,
		AddedAt:      it.saved.AddedAt,
	}
	stats := t.Stats()
	st.Peers = stats.ActivePeers
	st.Seeders = stats.ConnectedSeeders
	st.KnownPeers = stats.TotalPeers

	if !st.HasMetadata {
		st.State = "metadata"
		return st
	}
	selected := map[int]bool{}
	for _, i := range it.saved.Selected {
		selected[i] = true
	}
	for i, f := range t.Files() {
		done := f.BytesCompleted()
		if selected[i] {
			st.Length += f.Length()
			st.BytesCompleted += done
		}
		if withFiles {
			st.Files = append(st.Files, FileStatus{
				Index:          i,
				Path:           f.DisplayPath(),
				Length:         f.Length(),
				BytesCompleted: done,
				Selected:       selected[i],
			})
		}
	}
	switch {
	case it.saved.Selected == nil:
		st.State = "waiting" // Metadata known, user hasn't picked files
	case it.saved.Paused:
		st.State = "paused"
	case st.Length > 0 && st.BytesCompleted >= st.Length:
		if e.seed {
			st.State = "seeding"
		} else {
			st.State = "completed"
		}
	default:
		st.State = "downloading"
	}
	return st
}

func (e *Engine) List(withFiles bool) []TorrentStatus {
	e.mu.Lock()
	defer e.mu.Unlock()
	out := make([]TorrentStatus, 0, len(e.items))
	for _, it := range e.items {
		out = append(out, e.statusLocked(it, withFiles))
	}
	return out
}

func (e *Engine) Get(id string) (TorrentStatus, error) {
	e.mu.Lock()
	defer e.mu.Unlock()
	it, ok := e.items[id]
	if !ok {
		return TorrentStatus{}, errNotFound
	}
	return e.statusLocked(it, true), nil
}

// tick updates transfer rates and stops uploading finished torrents when
// seeding is off.
func (e *Engine) tick() {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-e.stop:
			return
		case now := <-ticker.C:
			e.mu.Lock()
			for _, it := range e.items {
				stats := it.t.Stats()
				down := stats.BytesReadUsefulData.Int64()
				up := stats.BytesWrittenData.Int64()
				dt := now.Sub(it.lastAt).Seconds()
				if dt > 0 {
					// Light smoothing so the UI doesn't jump around.
					it.rateDown = 0.6*float64(down-it.lastDown)/dt + 0.4*it.rateDown
					it.rateUp = 0.6*float64(up-it.lastUp)/dt + 0.4*it.rateUp
				}
				it.lastDown, it.lastUp, it.lastAt = down, up, now
				if it.t.Info() != nil && it.saved.Selected != nil && !it.saved.Paused {
					st := e.statusLocked(it, false)
					finished := st.State == "completed" || st.State == "seeding"
					if finished && !e.seed {
						// Done and not seeding: stop sharing and drop peers.
						it.t.DisallowDataUpload()
						it.t.SetMaxEstablishedConns(0)
					} else {
						it.t.AllowDataUpload()
						it.t.SetMaxEstablishedConns(e.maxConns)
					}
				}
			}
			e.mu.Unlock()
		}
	}
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

func (e *Engine) saveLocked() {
	list := make([]savedTorrent, 0, len(e.items))
	for _, it := range e.items {
		list = append(list, it.saved)
	}
	data, err := json.MarshalIndent(list, "", "  ")
	if err != nil {
		return
	}
	tmp := e.stateFile + ".tmp"
	if os.WriteFile(tmp, data, 0o644) == nil {
		_ = os.Rename(tmp, e.stateFile)
	}
}

func (e *Engine) restore() {
	data, err := os.ReadFile(e.stateFile)
	if err != nil {
		return
	}
	var list []savedTorrent
	if json.Unmarshal(data, &list) != nil {
		return
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, saved := range list {
		if _, err := e.addLocked(saved); err != nil {
			slog.Warn("could not restore torrent", "infoHash", saved.InfoHash, "err", err)
		}
	}
}
