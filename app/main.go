// Minimal HTTP service used to exercise the deployment pipeline.
//
// Endpoints:
//   GET /        - service identity + build metadata
//   GET /health  - liveness probe (used by the ALB target group)
//   GET /ready   - readiness probe (kept separate from /health on purpose)
//
// Standard library only — no third-party deps means a tiny static binary
// and no supply-chain surface area for a demo service.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Injected at build time via -ldflags. See Dockerfile.
var (
	appVersion = "dev"
	gitSHA     = "unknown"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}

	hostname, _ := os.Hostname()

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
			"host":    hostname,
			"time":    time.Now().UTC().Format(time.RFC3339),
		})
	})

	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/ready", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           logRequest(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Graceful shutdown: ECS sends SIGTERM, we drain in-flight requests.
	go func() {
		log.Printf("listening on :%s version=%s sha=%s", port, appVersion, gitSHA)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	log.Println("shutdown signal received")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// Structured-ish access log. CloudWatch picks this up via the awslogs driver.
func logRequest(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("method=%s path=%s remote=%s duration_ms=%d",
			r.Method, r.URL.Path, r.RemoteAddr, time.Since(start).Milliseconds())
	})
}
