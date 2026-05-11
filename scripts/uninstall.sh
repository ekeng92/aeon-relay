#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════
#  AEON Relay — Uninstall
# ═══════════════════════════════════════════════════════════

APP_NAME="AEON Relay"
BINARY_NAME="AEONRelay"
INSTALL_DIR="$HOME/Applications"
RELAY_HOME="$HOME/.aeon-relay"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

info()  { echo "  ${CYAN}▸${RESET} $1"; }
ok()    { echo "  ${GREEN}✓${RESET} $1"; }

echo ""
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo "${BOLD}  📡 AEON Relay — Uninstall${RESET}"
echo "${BOLD}═══════════════════════════════════════════${RESET}"
echo ""

# Stop running instance
if pgrep -x "$BINARY_NAME" >/dev/null 2>&1; then
    info "Stopping $APP_NAME..."
    pkill -x "$BINARY_NAME" 2>/dev/null || true
    sleep 1
    ok "Stopped"
fi

# Remove app bundle
if [[ -d "$INSTALL_DIR/$APP_NAME.app" ]]; then
    info "Removing app bundle..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    ok "Removed $INSTALL_DIR/$APP_NAME.app"
fi

# Ask about config
echo ""
echo "  ${YELLOW}Config directory: $RELAY_HOME${RESET}"
echo "  This contains your channel configs, profiles, and audit logs."
read -p "  Delete config directory? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$RELAY_HOME"
    ok "Config directory removed"
else
    ok "Config directory kept"
fi

echo ""
echo "  ${GREEN}AEON Relay uninstalled.${RESET}"
echo ""
