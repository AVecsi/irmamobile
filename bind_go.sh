#!/usr/bin/env bash
set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")
GO_DIR="$SCRIPT_DIR"  # adjust if go.mod is in a subdirectory e.g. "$SCRIPT_DIR/go"

# ── Find pq-gabi in the Go module cache ─────────────────────────────────────

cd "$GO_DIR"
go mod download

PQ_GABI_DIR=$(go list -m -f '{{.Dir}}' github.com/AVecsi/pq-gabi)
echo "Found pq-gabi at: $PQ_GABI_DIR"

# ── Build zkDilithium for Android ───────────────────────────────────────────

chmod -R u+w "$PQ_GABI_DIR"

# Install required Rust targets if not already present
rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android

cd "$PQ_GABI_DIR"
make build-android

# ── gomobile bind ────────────────────────────────────────────────────────────

cd "$GO_DIR"
$(go env GOPATH)/bin/gomobile bind \
    -target android/arm,android/arm64 \
    -androidapi 26 \
    -o "$SCRIPT_DIR/android/irmagobridge/irmagobridge.aar" \
    ./irmagobridge

#/Users/vecsiadam/go/bin/gomobile bind -target android -androidapi 23 -o android/irmagobridge/irmagobridge.aar ./irmagobridge
#/Users/vecsiadam/go/bin/gomobile bind -target ios -iosversion 12.0 -o ios/Runner/Irmagobridge.xcframework github.com/privacybydesign/irmamobile/irmagobridge
