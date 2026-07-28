#!/usr/bin/env bash
#
# Build the irmagobridge .aar for the Flutter app, selecting the crypto backend.
#
#   ./bind_go.sh                      # default backend (zkdilithium)
#   ./bind_go.sh --backend lazer      # Falcon-512 / LNP lattice backend
#   ./bind_go.sh -b lazer --targets android/arm64 --api 26
#
# Backend selection is by Go build tag (see pq-gabi/internal/scheme):
#   zkdilithium -> //go:build !lazer  (no tag)     native: Rust (libzk_dilithium.a)
#   lazer       -> //go:build lazer   (-tags lazer) native: C   (liblazer+HEXL+GMP+MPFR)
#
# Adding a backend later = one entry in the `case "$BACKEND"` block below plus a
# prepare_<name>() function that stages its native libraries for Android.
set -euo pipefail

SCRIPT_DIR=$(dirname "$(realpath "$0")")
GO_DIR="$SCRIPT_DIR" # adjust if go.mod lives in a subdirectory

# ── defaults ────────────────────────────────────────────────────────────────
BACKEND="zkdilithium"
TARGETS="android/arm,android/arm64"
ANDROIDAPI=26
OUT="$SCRIPT_DIR/android/irmagobridge/irmagobridge.aar"

usage() {
  cat <<EOF
usage: $(basename "$0") [options]
  -b, --backend <name>   crypto backend: zkdilithium (default) | lazer
      --targets <list>   gomobile targets (default: $TARGETS)
      --api <n>          Android API level (default: $ANDROIDAPI)
  -o, --out <path>       output .aar (default: $OUT)
  -h, --help             this help
EOF
}

# ── arg parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b | --backend) BACKEND="$2"; shift 2 ;;
    --targets)      TARGETS="$2"; shift 2 ;;
    --api)          ANDROIDAPI="$2"; shift 2 ;;
    -o | --out)     OUT="$2"; shift 2 ;;
    -h | --help)    usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 1 ;;
  esac
done

# ── helpers ─────────────────────────────────────────────────────────────────
module_dir() { # resolve a (possibly replaced/local) module to its directory
  ( cd "$GO_DIR" && go list -m -f '{{.Dir}}' "$1" )
}

# Map a gomobile target ("android/arm64") to the Android ABI dir name.
abi_of() {
  case "$1" in
    android/arm64) echo "arm64-v8a" ;;
    android/arm)   echo "armeabi-v7a" ;;
    android/amd64) echo "x86_64" ;;
    android/386)   echo "x86" ;;
    *) echo "error: unsupported target '$1'" >&2; return 1 ;;
  esac
}

# ── backend: zkdilithium (Rust) ─────────────────────────────────────────────
prepare_zkdilithium() {
  local pqdir; pqdir=$(module_dir github.com/AVecsi/pq-gabi)
  echo "[zkdilithium] pq-gabi at: $pqdir"
  chmod -R u+w "$pqdir" 2>/dev/null || true
  rustup target add aarch64-linux-android armv7-linux-androideabi \
    i686-linux-android x86_64-linux-android
  ( cd "$pqdir" && make build-android )
}

# ── backend: lazer (C: liblazer + Intel HEXL + GMP + MPFR) ───────────────────
# The lazer binding links a per-ABI C static-lib stack. Unlike Rust, these are
# not produced by `rustup`; they must be cross-compiled with the Android NDK and
# staged under <lazer-binding>/android/<abi>/{liblazer,libhexl,libmpfr,libgmp}.a
# (and the binding needs a matching `#cgo android,<arch> LDFLAGS:` stanza).
prepare_lazer() {
  local lazerdir; lazerdir=$(module_dir github.com/AVecsi/lazer)
  local lazerroot; lazerroot=$(cd "$lazerdir/../.." && pwd) # golang/lazer -> repo root
  echo "[lazer] binding at: $lazerdir"
  echo "[lazer] lazer repo: $lazerroot"
  chmod -R u+w "$lazerdir" 2>/dev/null || true

  # Build the native stack if the repo provides a cross-build hook.
  local hook="$lazerroot/scripts/build-android.sh"
  if [[ -x "$hook" ]]; then
    echo "[lazer] running $hook"
    "$hook" --targets "$TARGETS" --api "$ANDROIDAPI"
  fi

  # Verify the per-ABI static libs exist for every requested target.
  local missing=0 t abi lib
  IFS=',' read -ra _targets <<< "$TARGETS"
  for t in "${_targets[@]}"; do
    abi=$(abi_of "$t")
    for lib in liblazer.a libhexl.a libmpfr.a libgmp.a; do
      if [[ ! -f "$lazerdir/android/$abi/$lib" ]]; then
        echo "[lazer] MISSING: android/$abi/$lib" >&2
        missing=1
      fi
    done
  done
  if [[ $missing -ne 0 ]]; then
    cat >&2 <<EOF

[lazer] The Android C stack is not built yet. Cross-compile it for the NDK and
stage it under: $lazerdir/android/<abi>/
  required per ABI: liblazer.a  libhexl.a  libmpfr.a  libgmp.a
  toolchain: \$ANDROID_NDK_HOME clang for aarch64-linux-android (+ armv7 for 32-bit)
    GMP/MPFR : autotools ./configure --host=<abi-triple> CC=<ndk-clang>
    HEXL     : cmake -DCMAKE_TOOLCHAIN_FILE=\$NDK/build/cmake/android.toolchain.cmake -DANDROID_ABI=<abi>
    liblazer : make with CC=<ndk-clang> and the ARM (ARCH_ARM) path, no LaBRADOR
The binding also needs a '#cgo android,<arch> LDFLAGS:' stanza pointing at these.
(Drop a scripts/build-android.sh in the lazer repo to automate this; the script
will then invoke it automatically.)
EOF
    exit 1
  fi
}

# ── select backend ──────────────────────────────────────────────────────────
BUILD_TAGS=""
case "$BACKEND" in
  zkdilithium) BUILD_TAGS="";      prepare_zkdilithium ;;
  lazer)       BUILD_TAGS="lazer"; prepare_lazer ;;
  *) echo "error: unknown backend '$BACKEND' (expected: zkdilithium | lazer)" >&2; exit 1 ;;
esac

# ── gomobile bind ────────────────────────────────────────────────────────────
cd "$GO_DIR"
go mod download

GOMOBILE="$(go env GOPATH)/bin/gomobile"
tagflag=()
[[ -n "$BUILD_TAGS" ]] && tagflag=(-tags "$BUILD_TAGS")

echo "[bind] backend=$BACKEND tags='${BUILD_TAGS}' targets=$TARGETS -> $OUT"
"$GOMOBILE" bind \
  -target "$TARGETS" \
  -androidapi "$ANDROIDAPI" \
  "${tagflag[@]}" \
  -o "$OUT" \
  ./irmagobridge

echo "[bind] done: $OUT"

# iOS (future): mirror the above with -target ios/... and per-backend prepare_*.
#   $GOMOBILE bind -target ios -iosversion 12.0 -tags "$BUILD_TAGS" \
#     -o ios/Runner/Irmagobridge.xcframework ./irmagobridge
