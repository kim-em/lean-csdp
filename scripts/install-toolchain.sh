#!/usr/bin/env bash
# Install the Lean toolchain pinned in lean-toolchain, with a GitHub-release
# fallback for when the canonical release server is flaky.
#
# Usage: ./scripts/install-toolchain.sh
#
# Requires elan to already be on PATH. Honours $LEAN_TOOLCHAIN_RETRIES (default 5).

set -euo pipefail

if ! command -v elan >/dev/null 2>&1; then
  echo "elan not on PATH; please install elan first" >&2
  exit 1
fi

TOOLCHAIN="$(tr -d '\r\n' < lean-toolchain)"
RETRIES="${LEAN_TOOLCHAIN_RETRIES:-5}"

# Try the normal `elan toolchain install` path first; this is fast when the
# upstream release infrastructure is healthy and benefits from elan's
# manifest verification.
for attempt in $(seq 1 "$RETRIES"); do
  if elan toolchain install "$TOOLCHAIN"; then
    elan default "$TOOLCHAIN"
    lean --version
    exit 0
  fi
  echo "Toolchain install attempt $attempt failed; retrying in 30s..." >&2
  sleep 30
done

echo "elan-driven install failed $RETRIES times; falling back to direct GitHub release download." >&2

# Fallback: download the official tarball from github.com/leanprover/lean4
# releases, extract it into elan's toolchain directory, and let elan pick it
# up by name. This sidesteps any outages on the canonical release server.
case "$TOOLCHAIN" in
  leanprover/lean4:*)
    VERSION="${TOOLCHAIN#leanprover/lean4:}"
    ;;
  *)
    echo "Toolchain $TOOLCHAIN is not in the form leanprover/lean4:VERSION; cannot fall back." >&2
    exit 1
    ;;
esac

uname_out="$(uname -s)"
case "$uname_out" in
  Linux)
    ARCH="linux"
    ;;
  Darwin)
    case "$(uname -m)" in
      arm64|aarch64) ARCH="darwin_aarch64" ;;
      *)             ARCH="darwin" ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*)
    ARCH="windows"
    ;;
  *)
    echo "Unsupported uname: $uname_out" >&2
    exit 1
    ;;
esac

ELAN_DIR="${ELAN_HOME:-$HOME/.elan}"
SANITIZED="$(printf '%s' "$TOOLCHAIN" | sed 's|/|--|; s|:|---|')"
DEST="$ELAN_DIR/toolchains/$SANITIZED"

if [ -d "$DEST" ] && [ -x "$DEST/bin/lean" ]; then
  echo "Toolchain already extracted at $DEST"
else
  mkdir -p "$DEST"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  if [ "$ARCH" = "windows" ]; then
    EXT="zip"
  else
    EXT="tar.zst"
  fi
  ASSET="lean-${VERSION#v}-${ARCH}.${EXT}"
  URL="https://github.com/leanprover/lean4/releases/download/${VERSION}/${ASSET}"
  echo "Downloading $URL"
  curl -fSL --retry 5 --retry-delay 10 -o "$TMP/$ASSET" "$URL"

  case "$EXT" in
    tar.zst)
      tar --use-compress-program='zstd -d' -xf "$TMP/$ASSET" -C "$DEST" --strip-components=1
      ;;
    zip)
      unzip -q "$TMP/$ASSET" -d "$TMP/extracted"
      # The zip contains a single top-level directory; move its contents up.
      inner="$(find "$TMP/extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
      if [ -z "$inner" ]; then
        echo "Could not locate top-level directory inside $ASSET" >&2
        exit 1
      fi
      cp -R "$inner"/. "$DEST/"
      ;;
  esac
fi

elan default "$TOOLCHAIN"
lean --version
