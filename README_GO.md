# Embedded Camera UI - Go Server Setup

## Project Structure

```
goWeb/
├── src/                          # Vue.js frontend source
│   ├── components/
│   │   └── CameraConfig.vue
│   ├── App.vue
│   └── main.ts
├── dist/                         # ✅ BUILD OUTPUT (copy this to embedded device)
│   ├── index.html
│   ├── assets/
│   │   ├── main-*.js
│   │   └── main-*.css
│   └── ...
├── cmd/server/                   # Go server
│   └── main.go
├── go.mod
├── go.sum
├── package.json                  # Vue build scripts
├── vite.config.ts
└── tsconfig.json
```

## Build & Deploy Flow

### Step 1: Build Vue.js UI on your dev machine

```bash
cd /Users/KC/workplace/goWeb
npm install
npm run build
```

This generates the `dist/` folder containing all static assets.

### Step 2: Copy dist/ to your embedded device

```bash
# Option A: Copy entire dist folder
scp -r dist/ root@embedded-device:/home/camera/ui/

# Option B: Manual copy if using file transfer
# Put the dist/ folder alongside your Go server on the device
```

### Step 3: Run the Go server on the embedded device

```bash
# On your dev machine (to build for embedded Linux ARM)
GOOS=linux GOARCH=arm64 go build -o camera-ui-server ./cmd/server/main.go

# Then copy to device
scp camera-ui-server root@embedded-device:/home/camera/

# On the embedded device
cd /home/camera
./camera-ui-server
```

Or compile directly on the device:

```bash
# On embedded device
cd /home/camera/goWeb
go run ./cmd/server/main.go
```

### Step 4: Access the UI

Open browser: `http://<embedded-device-ip>:8080`

## File Placement on Embedded Device

```
/home/camera/
├── camera-ui-server        # Compiled Go binary
└── dist/                   # Static files from npm build
    ├── index.html
    ├── assets/
    │   ├── main-*.js       # Vue app bundle
    │   └── main-*.css      # Styles
    └── favicon.ico
```

## Development vs Production

**Development (on your machine):**
```bash
npm run dev          # Dev server with hot reload at http://localhost:5173
```

**Production (on embedded device):**
```bash
npm run build        # Build Vue app once
go run ./cmd/server/main.go  # Serve dist/ folder via Go on :8080
```

## API Endpoint

The Go server provides a demo endpoint:

- **URL:** `POST /api/camera/config`
- **Request:**
```json
{
  "resolution": "4k",
  "bitrate": 15
}
```
- **Response:**
```json
{
  "success": true,
  "message": "Camera configuration updated: resolution=4k, bitrate=15 Mbps"
}
```

Edit `cmd/server/main.go` to connect to your actual camera SDK/firmware.

## For Embedded Devices with No npm

1. Build on dev machine → generates `dist/`
2. Copy `dist/` to device
3. Run Go server on device to serve static files

That's it! No npm required on the embedded device.

## Docker (Optional)

If your device supports Docker:

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY . .
RUN go build -o camera-ui-server ./cmd/server/main.go

FROM alpine:latest
WORKDIR /home/camera
COPY --from=builder /app/camera-ui-server .
COPY --from=builder /app/dist ./dist
EXPOSE 8080
CMD ["./camera-ui-server"]
```

Build & run:
```bash
docker build -t camera-ui .
docker run -p 8080:8080 camera-ui
```
