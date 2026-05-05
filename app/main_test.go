package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// We re-build the same routes here rather than exporting them, to keep main.go
// flat and dependency-free. If the surface grows, extract a router builder.
func newTestServer() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"service": "devops-challenge",
			"version": appVersion,
			"git_sha": gitSHA,
		})
	})
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("/ready", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})
	return mux
}

func TestRoot(t *testing.T) {
	srv := httptest.NewServer(newTestServer())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	var body map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["service"] != "devops-challenge" {
		t.Errorf("unexpected service: %v", body["service"])
	}
}

func TestHealth(t *testing.T) {
	srv := httptest.NewServer(newTestServer())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/health")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
}

func TestReady(t *testing.T) {
	srv := httptest.NewServer(newTestServer())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/ready")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
}

func TestUnknownPath404(t *testing.T) {
	srv := httptest.NewServer(newTestServer())
	defer srv.Close()

	resp, err := http.Get(srv.URL + "/nope")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("want 404, got %d", resp.StatusCode)
	}
}
