#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
#  AEON Relay — Complete Installation
#  Works on any Mac with macOS 13+ and Xcode CommandLineTools
# ═══════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

AEON_HOME="${AEON_PREFIX:-$HOME}"
RELAY_HOME="$AEON_HOME/.aeon-relay"
APP_NAME="AEON Relay"
BINARY_NAME="AEONRelay"
INSTALL_DIR="$AEON_HOME/Applications"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

info()  { echo "  ${CYAN}▸${RESET} $1"; }
ok()    { echo "  ${GREEN}✓${RESET} $1"; }
warn()  { echo "  ${YELLOW}⚠${RESET} $1"; }
fail()  { echo "  ${RED}✗${RESET} $1"; exit 1; }

echo ""
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo "${BOLD}  📡 AEON Relay — Installation${RESET}"
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo ""

# ── Step 1: Check macOS version ────────────────────────────────────────

info "Checking macOS version..."
MACOS_VERSION="$(sw_vers -productVersion)"
MAJOR="$(echo "$MACOS_VERSION" | cut -d. -f1)"
if (( MAJOR < 13 )); then
    fail "macOS 13 (Ventura) or later required. You have $MACOS_VERSION."
fi
ok "macOS $MACOS_VERSION"

# ── Step 2: Check Swift toolchain ──────────────────────────────────────

info "Checking Swift toolchain..."
if ! command -v swift &>/dev/null; then
    fail "Swift not found. Install Xcode CommandLineTools: xcode-select --install"
fi
SWIFT_VERSION="$(swift --version 2>&1 | head -1)"
ok "$SWIFT_VERSION"

# ── Step 3: Create config directories ─────────────────────────────────

info "Creating config directories..."
mkdir -p "$RELAY_HOME"/{channels,profiles,audit,logs}
ok "$RELAY_HOME"

# ── Step 4: Build app ─────────────────────────────────────────────────

info "Compiling $APP_NAME (this may take a minute on first build)..."
cd "$PROJECT_DIR"
make app 2>&1 | tail -3
ok "Build complete"

# ── Step 5: Install ───────────────────────────────────────────────────

info "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
if pgrep -x "$BINARY_NAME" >/dev/null 2>&1; then
    info "Stopping running instance..."
    pkill -x "$BINARY_NAME" 2>/dev/null || true
    sleep 1
fi
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$INSTALL_DIR/"
codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
touch "$INSTALL_DIR/$APP_NAME.app"
ok "Installed to $INSTALL_DIR/$APP_NAME.app"

# ── Step 6: Launch ────────────────────────────────────────────────────

info "Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"
ok "Running"

echo ""
echo "${BOLD}  Installation complete!${RESET}"
echo ""
echo "  Configure channels:  ${CYAN}$RELAY_HOME/channels/${RESET}"
echo "  Configure profiles:  ${CYAN}$RELAY_HOME/profiles/${RESET}"
echo "  Audit logs:          ${CYAN}$RELAY_HOME/audit/${RESET}"
echo ""
