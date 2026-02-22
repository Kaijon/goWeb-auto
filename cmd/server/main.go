package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
)

func main() {
	// Determine the dist directory
	// When running from project root: ./dist
	// When running from embedded device: adjust path as needed
	distDir := "./dist"

	// Check if dist directory exists
	if _, err := os.Stat(distDir); os.IsNotExist(err) {
		log.Fatalf("dist directory not found at %s. Please build the Vue app first: npm run build", distDir)
	}

	// Create a file server for the dist directory
	fileServer := http.FileServer(http.Dir(distDir))

	// Middleware to handle SPA routing (fallback to index.html for non-existent files)
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// If the requested path doesn't exist as a file, serve index.html
		fullPath := filepath.Join(distDir, r.URL.Path)
		
		// Check if path is a file that exists
		fileInfo, err := os.Stat(fullPath)
		if err != nil || fileInfo.IsDir() {
			// Not a file (either doesn't exist or is a directory)
			// For API routes, let them through
			if r.URL.Path != "/" && (filepath.Ext(r.URL.Path) == "" || filepath.Ext(r.URL.Path) == "/") {
				// This is likely a Vue route, serve index.html
				http.ServeFile(w, r, filepath.Join(distDir, "index.html"))
				return
			}
		}
		
		// Serve the file normally
		fileServer.ServeHTTP(w, r)
	})

	// API endpoint for camera configuration
	http.HandleFunc("/api/camera/config", handleCameraConfig)

	// Server setup
	port := ":8080"
	addr := "0.0.0.0:8080"

	fmt.Printf("🎥 Embedded Camera UI Server\n")
	fmt.Printf("📁 Serving static files from: %s\n", distDir)
	fmt.Printf("🌐 Server listening on %s\n", port)
	fmt.Printf("📍 Open http://localhost:8080 in your browser\n")

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// handleCameraConfig handles POST requests to /api/camera/config
func handleCameraConfig(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")

	defer r.Body.Close()

	// Parse JSON request body
	var req struct {
		Resolution string `json:"resolution"`
		Bitrate    int    `json:"bitrate"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, `{"success":false,"message":"Invalid JSON payload","errorCode":"0x01"}`)
		return
	}

	// Validate resolution and bitrate
	if req.Resolution == "" {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, `{"success":false,"message":"Resolution is required","errorCode":"0x01"}`)
		return
	}

	// Check if bitrate is within valid range for the resolution
	if !isValidConfiguration(req.Resolution, req.Bitrate) {
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, `{"success":false,"message":"Invalid bitrate for resolution %s: %d Mbps","errorCode":"0x01"}`,
			req.Resolution, req.Bitrate)
		return
	}

	// Success
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"success":true,"message":"Camera configuration updated: resolution=%s, bitrate=%d Mbps","errorCode":""}`,
		req.Resolution, req.Bitrate)
}

// isValidConfiguration checks if the resolution/bitrate combination is valid per bitrate-policy.md
func isValidConfiguration(resolution string, bitrate int) bool {
	switch resolution {
	case "4k":
		// 4K: 8-16 Mbps
		return bitrate >= 8 && bitrate <= 16
	case "2k":
		// 2K: 6-12 Mbps
		return bitrate >= 6 && bitrate <= 12
	case "1080p":
		// 1080P: < 6 Mbps (0-5 range)
		return bitrate >= 0 && bitrate < 6
	default:
		return false
	}
}
