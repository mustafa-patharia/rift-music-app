#!/bin/bash
# Builds the two files YtDlpManager bundles: a relocatable arm64 CPython
# and yt-dlp packaged for zipimport. Both are gitignored (15 MB of binaries)
# so a fresh clone needs this to produce a working app. Idempotent — skips
# work if the outputs already exist.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES="$ROOT/Rift/Resources"
PY_TARBALL="$RES/python-arm64.tar.gz"
YTDLP_ZIP="$RES/yt-dlp.zip"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$RES"

# ---- relocatable CPython (python-build-standalone, arm64 macOS) ----
if [[ ! -f "$PY_TARBALL" ]]; then
    echo "fetch-engine: fetching relocatable CPython…"
    ASSET_URL=$(curl -fsSL https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest \
        | python3 -c '
import json, sys
d = json.load(sys.stdin)
for a in d["assets"]:
    n = a["name"]
    if (n.startswith("cpython-3.12.") and n.endswith("install_only_stripped.tar.gz")
            and "aarch64-apple-darwin" in n):
        print(a["browser_download_url"])
        break
')
    if [[ -z "$ASSET_URL" ]]; then
        echo "fetch-engine: could not find a python-build-standalone macOS arm64 asset" >&2
        exit 1
    fi
    curl -fsSL "$ASSET_URL" -o "$WORK/python.tar.gz"
    # Re-root the archive's top-level "python/" dir so it unpacks flat, matching
    # what YtDlpManager expects at pyRootURL (bin/python3 at the tarball root).
    mkdir -p "$WORK/pyroot"
    tar xzf "$WORK/python.tar.gz" -C "$WORK/pyroot" --strip-components=1
    tar czf "$PY_TARBALL" -C "$WORK/pyroot" .
    echo "fetch-engine: python-arm64.tar.gz ready"
else
    echo "fetch-engine: python-arm64.tar.gz already present, skipping"
fi

# ---- yt-dlp, packaged for zipimport ----
if [[ ! -f "$YTDLP_ZIP" ]]; then
    echo "fetch-engine: packaging yt-dlp for zipimport…"
    PYBIN="$WORK/pyroot/bin/python3"
    [[ -x "$PYBIN" ]] || PYBIN="python3"
    "$PYBIN" -m pip install --quiet --no-compile --target "$WORK/ytdlp-pkg" yt-dlp
    rm -rf "$WORK/ytdlp-pkg"/*.dist-info "$WORK/ytdlp-pkg/bin"
    # zipimport runs __main__.py at the zip root, not yt_dlp/__main__.py.
    printf 'import yt_dlp\nyt_dlp.main()\n' > "$WORK/ytdlp-pkg/__main__.py"
    (cd "$WORK/ytdlp-pkg" && zip -qr "$YTDLP_ZIP" .)
    echo "fetch-engine: yt-dlp.zip ready"
else
    echo "fetch-engine: yt-dlp.zip already present, skipping"
fi
