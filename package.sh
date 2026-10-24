#!/usr/bin/env bash
# package.sh — Build and package procTree into a distributable zip
# Usage: ./package.sh [version]
#   version: optional override (default: latest git tag or "1.0.0")
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
GREEN=$'\e[32m'; YELLOW=$'\e[33m'; CYAN=$'\e[36m'; RED=$'\e[31m'

info()    { echo "${CYAN}▸${RESET} $*"; }
success() { echo "${GREEN}✔${RESET} $*"; }
warn()    { echo "${YELLOW}⚠${RESET} $*"; }
die()     { echo "${RED}✖${RESET} $*" >&2; exit 1; }

# ── Config ────────────────────────────────────────────────────────────────────
BINARY_NAME="procTree"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve version: CLI arg → git tag → fallback
if [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    VERSION="$1"
elif git -C "$SCRIPT_DIR" describe --tags --exact-match HEAD 2>/dev/null | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+$'; then
    VERSION="$(git -C "$SCRIPT_DIR" describe --tags --exact-match HEAD | sed 's/^v//')"
elif git -C "$SCRIPT_DIR" describe --tags 2>/dev/null | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+'; then
    VERSION="$(git -C "$SCRIPT_DIR" describe --tags | sed 's/^v//; s/-[0-9]*-g[0-9a-f]*//')"
else
    VERSION="1.0.0"
    warn "No git tag found — using version ${VERSION}"
fi

ARCH="$(uname -m)"          # arm64 or x86_64
OS="macos"
DIST_NAME="${BINARY_NAME}-${VERSION}-${OS}-${ARCH}"
DIST_DIR="${SCRIPT_DIR}/dist/${DIST_NAME}"
ZIP_PATH="${SCRIPT_DIR}/dist/${DIST_NAME}.zip"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "${BOLD}  ⬡  procTree — distributable packager${RESET}"
echo "${DIM}  version ${VERSION}  ·  ${OS}-${ARCH}${RESET}"
echo ""

# ── Step 1: Build ─────────────────────────────────────────────────────────────
info "Building release binary (swift build -c release) …"
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | sed "s/^/  ${DIM}/"
printf "${RESET}"

# Locate binary (SPM layout)
BINARY_PATH="${SCRIPT_DIR}/.build/release/${BINARY_NAME}"
[[ -f "$BINARY_PATH" ]] || die "Binary not found at ${BINARY_PATH}"
success "Binary built: ${DIM}${BINARY_PATH}${RESET}"

# ── Step 2: Strip debug symbols ───────────────────────────────────────────────
info "Stripping debug symbols …"
strip -S "$BINARY_PATH"
success "Stripped"

# ── Step 3: Stage dist directory ─────────────────────────────────────────────
info "Staging dist directory …"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$BINARY_PATH"               "$DIST_DIR/${BINARY_NAME}"
cp "${SCRIPT_DIR}/README.md"    "$DIST_DIR/README.md"

# Write an install helper script into the package
cat > "$DIST_DIR/install.sh" <<'INSTALLER'
#!/usr/bin/env bash
# install.sh — Install procTree to /usr/local/bin
set -euo pipefail
DEST="/usr/local/bin/procTree"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="${SCRIPT_DIR}/procTree"

if [[ ! -f "$BINARY" ]]; then
    echo "Error: binary not found at ${BINARY}" >&2; exit 1
fi

if [[ ! -w "$(dirname "$DEST")" ]]; then
    echo "Installing to ${DEST} (requires sudo) …"
    sudo install -m 755 "$BINARY" "$DEST"
else
    install -m 755 "$BINARY" "$DEST"
fi

echo "✔ procTree installed to ${DEST}"
echo "  Run: procTree"
echo "  (sudo recommended for full thread inspection)"
INSTALLER
chmod +x "$DIST_DIR/install.sh"

success "Staged: ${DIM}${DIST_DIR}${RESET}"

# ── Step 4: Zip ───────────────────────────────────────────────────────────────
info "Creating zip archive …"
rm -f "$ZIP_PATH"
cd "${SCRIPT_DIR}/dist"
zip -r --quiet "${DIST_NAME}.zip" "${DIST_NAME}/"
success "Package ready: ${GREEN}${BOLD}dist/${DIST_NAME}.zip${RESET}"

# ── Summary ───────────────────────────────────────────────────────────────────
BINARY_SIZE="$(du -sh "$DIST_DIR/${BINARY_NAME}" | cut -f1)"
ZIP_SIZE="$(du -sh "$ZIP_PATH" | cut -f1)"

echo ""
echo "  ${BOLD}Binary${RESET}   ${BINARY_SIZE}   ${DIM}${DIST_DIR}/${BINARY_NAME}${RESET}"
echo "  ${BOLD}Archive${RESET}  ${ZIP_SIZE}   ${DIM}${ZIP_PATH}${RESET}"
echo ""
echo "${GREEN}${BOLD}  Done.${RESET} Distribute ${BOLD}dist/${DIST_NAME}.zip${RESET}"
echo "         Recipients run ${BOLD}./install.sh${RESET} inside the archive to install."
echo ""
