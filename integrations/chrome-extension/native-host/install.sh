#!/usr/bin/env bash
# Install (or remove) the MacParakeet Chrome native messaging host (ADR-029).
#
# Native messaging manifests can only point at a bare executable path — no
# arguments — so this writes a tiny wrapper script that execs
# `macparakeet-cli chrome-native-host`, then registers it with every
# Chromium-family browser found on this machine, and finally enables the
# opt-in bridge preference (that step is the explicit user consent moment).
#
# Usage:
#   ./install.sh                 # auto-detect macparakeet-cli
#   ./install.sh /path/to/macparakeet-cli
#   ./install.sh --uninstall
set -euo pipefail

HOST_NAME="com.macparakeet.chrome_bridge"
EXTENSION_ID="jeiadfgefgjejfblpgpgiihakgpcebfm"  # pinned via "key" in manifest.json
SUPPORT_DIR="$HOME/Library/Application Support/MacParakeet/chrome-bridge"
WRAPPER="$SUPPORT_DIR/chrome-bridge-host.sh"

# NativeMessagingHosts directories for Chromium-family browsers on macOS.
BROWSER_DIRS=(
  "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  "$HOME/Library/Application Support/Google/Chrome Beta/NativeMessagingHosts"
  "$HOME/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
  "$HOME/Library/Application Support/Chromium/NativeMessagingHosts"
  "$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
  "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
  "$HOME/Library/Application Support/Arc/User Data/NativeMessagingHosts"
  "$HOME/Library/Application Support/Vivaldi/NativeMessagingHosts"
)

log() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

uninstall() {
  local removed=0
  for dir in "${BROWSER_DIRS[@]}"; do
    if [ -f "$dir/$HOST_NAME.json" ]; then
      rm -f "$dir/$HOST_NAME.json"
      log "removed $dir/$HOST_NAME.json"
      removed=1
    fi
  done
  rm -f "$WRAPPER"
  if command -v macparakeet-cli >/dev/null 2>&1; then
    macparakeet-cli config set chrome-extension off >/dev/null || true
    log "disabled the chrome-extension bridge preference"
  fi
  [ "$removed" -eq 1 ] || log "no host manifests were installed"
  log "uninstall complete"
}

if [ "${1:-}" = "--uninstall" ]; then
  uninstall
  exit 0
fi

# --- Locate macparakeet-cli --------------------------------------------------

CLI="${1:-}"
if [ -z "$CLI" ]; then
  if command -v macparakeet-cli >/dev/null 2>&1; then
    CLI="$(command -v macparakeet-cli)"
  elif [ -x "/Applications/MacParakeet.app/Contents/MacOS/macparakeet-cli" ]; then
    CLI="/Applications/MacParakeet.app/Contents/MacOS/macparakeet-cli"
  else
    fail "macparakeet-cli not found. Install it (brew install moona3k/tap/macparakeet-cli) or pass its path: ./install.sh /path/to/macparakeet-cli"
  fi
fi
[ -x "$CLI" ] || fail "$CLI is not executable"

if ! "$CLI" chrome-native-host --help >/dev/null 2>&1; then
  fail "$CLI does not support 'chrome-native-host' — update macparakeet-cli and retry"
fi

# --- Wrapper (manifests cannot pass argv) ------------------------------------

mkdir -p "$SUPPORT_DIR"
cat > "$WRAPPER" <<WRAP
#!/bin/sh
exec "$CLI" chrome-native-host "\$@"
WRAP
chmod 755 "$WRAPPER"
log "wrote $WRAPPER"

# --- Host manifests -----------------------------------------------------------

MANIFEST_JSON=$(cat <<JSON
{
  "name": "$HOST_NAME",
  "description": "MacParakeet meeting recorder bridge",
  "path": "$WRAPPER",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXTENSION_ID/"]
}
JSON
)

installed=0
for dir in "${BROWSER_DIRS[@]}"; do
  # Only register with browsers that exist on this machine (their profile
  # parent directory is present); creating orphan config trees helps nobody.
  parent="$(dirname "$dir")"
  [ -d "$parent" ] || continue
  mkdir -p "$dir"
  printf '%s\n' "$MANIFEST_JSON" > "$dir/$HOST_NAME.json"
  log "registered $dir/$HOST_NAME.json"
  installed=1
done
[ "$installed" -eq 1 ] || fail "no Chromium-family browser profile directories found — start your browser once, then re-run"

# --- Opt in -------------------------------------------------------------------

"$CLI" config set chrome-extension on >/dev/null
log "enabled the chrome-extension bridge preference"

log ""
log "Done. Next steps:"
log "  1. Open chrome://extensions, enable Developer mode, and Load unpacked"
log "     from: $(cd "$(dirname "$0")/.." && pwd)"
log "  2. Restart the browser so it picks up the new native messaging host."
log "  3. Open MacParakeet, join a meeting, and click the parakeet icon."
