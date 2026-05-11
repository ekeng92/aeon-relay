#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
#  AEON Relay — Remote Installer
#  curl -fsSL https://raw.githubusercontent.com/ekeng92/aeon-relay/main/scripts/remote-install.sh | bash
# ═══════════════════════════════════════════════════════════

REPO="https://github.com/ekeng92/aeon-relay.git"
CLONE_DIR="${TMPDIR:-/tmp}/aeon-relay-install"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

info()  { echo "  ${CYAN}▸${RESET} $1"; }
ok()    { echo "  ${GREEN}✓${RESET} $1"; }
fail()  { echo "  ${RED}✗${RESET} $1"; exit 1; }

echo ""
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo "${BOLD}  📡 AEON Relay — Installer${RESET}"
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo ""

# ── Uninstall mode ─────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
    info "Downloading uninstall script..."
    UNINSTALL_URL="https://raw.githubusercontent.com/ekeng92/aeon-relay/main/scripts/uninstall.sh"
    curl -fsSL "$UNINSTALL_URL" | bash
    exit 0
fi

# ── Preflight ──────────────────────────────────────────────

info "Checking requirements..."
[[ "$(uname -s)" == "Darwin" ]] || fail "AEON Relay requires macOS."

MACOS_VERSION="$(sw_vers -productVersion)"
MAJOR="$(echo "$MACOS_VERSION" | cut -d. -f1)"
(( MAJOR >= 13 )) || fail "macOS 13+ required. You have $MACOS_VERSION."

if ! command -v swift &>/dev/null; then
    echo ""
    echo "  Swift not found. Installing Xcode CommandLineTools..."
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "  After installation, re-run:"
    echo "  curl -fsSL https://raw.githubusercontent.com/ekeng92/aeon-relay/main/scripts/remote-install.sh | bash"
    exit 1
fi
ok "Prerequisites met"

# ── Clone ──────────────────────────────────────────────────

info "Downloading AEON Relay..."
rm -rf "$CLONE_DIR"
git clone --depth 1 "$REPO" "$CLONE_DIR" 2>/dev/null
ok "Downloaded"

# ── Install ────────────────────────────────────────────────

cd "$CLONE_DIR"
bash scripts/install.sh

# ── Cleanup ────────────────────────────────────────────────

rm -rf "$CLONE_DIR"
