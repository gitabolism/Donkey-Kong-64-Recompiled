#!/usr/bin/env bash
#
# Launcher for a local DK64: Recompiled build. Runs the game from the repository
# root (it needs ./assets and ./recompcontrollerdb.txt) and writes a diagnostic
# log for every run, with a header describing the build and the machine state.
#
#   dk64_launcher.sh              start the game, log to a new timestamped file
#   dk64_launcher.sh --check      print paths and environment without launching
#   dk64_launcher.sh --logs       open the log directory
#   dk64_launcher.sh --tail       follow the newest log without launching
#
# Environment overrides:
#   DK64_REPO       repository to run (default: the one containing this script)
#   DK64_LOG_DIR    log directory (default: ~/.local/state/DK64Recompiled/logs)
#   DK64_ALLOW_MULTI=1  start even if another instance is already running
#
# Not part of the upstream project; see the note in setup_desktop_entry.sh.

set -uo pipefail

find_repo() {
    # Prefer the repository that contains this script, then the install-time hint.
    local candidate
    candidate="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    if [[ -x "$candidate/DK64Recompiled" ]]; then
        echo "$candidate"
        return 0
    fi
    if [[ -f "$candidate/.dk64_repo" ]]; then
        read -r candidate <"$candidate/.dk64_repo"
        echo "$candidate"
        return 0
    fi
    echo "$HOME/Projects/Donkey-Kong-64-Recompiled"
}

REPO="${DK64_REPO:-$(find_repo)}"
BIN="$REPO/DK64Recompiled"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/DK64Recompiled"
LOG_DIR="${DK64_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/DK64Recompiled/logs}"
KEEP_LOGS=20

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

newest_log() { ls -1t "$LOG_DIR"/dk64-*.log 2>/dev/null | head -1; }

mkdir -p "$LOG_DIR" || exit 1

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --logs) exec xdg-open "$LOG_DIR" ;;
    --tail)
        log_to_tail="$(newest_log)"
        [[ -n "$log_to_tail" ]] || { echo "no logs yet in $LOG_DIR"; exit 1; }
        echo "tail -f $log_to_tail"
        exec tail -f "$log_to_tail"
        ;;
esac

timestamp="$(date +%Y%m%d-%H%M%S)"
log_file="$LOG_DIR/dk64-${timestamp}.log"

if [[ "${1:-}" == "--check" ]]; then
    echo "repo:      $REPO"
    echo "binary:    $BIN"
    echo "config:    $CONFIG_DIR"
    echo "log dir:   $LOG_DIR"
    echo "next log:  $log_file"
    echo "newest:    $(newest_log || echo none)"
    [[ -x "$BIN" ]] && echo "binary:    OK" || echo "binary:    MISSING - build it first (./arch_build.sh)"
    exit 0
fi

if pgrep -x DK64Recompiled >/dev/null 2>&1 && [[ "${DK64_ALLOW_MULTI:-0}" != "1" ]]; then
    echo "DK64Recompiled is already running; not starting a second instance." >&2
    echo "Close it with: pkill DK64Recompiled   (or set DK64_ALLOW_MULTI=1)" >&2
    exit 1
fi

if [[ ! -x "$BIN" ]]; then
    echo "Missing executable: $BIN" >&2
    echo "Build it with: cd '$REPO' && ./arch_build.sh" >&2
    exit 1
fi

cd "$REPO" || exit 1
ln -sfn "$log_file" "$LOG_DIR/latest.log"

{
    echo "===== DK64: Recompiled launch log ====="
    echo "started:        $(date -Is)"
    echo "host:           $(uname -nr)"
    echo "desktop:        ${XDG_CURRENT_DESKTOP:-unknown} / session ${XDG_SESSION_TYPE:-unknown}"
    echo "repo:           $REPO"
    echo "git HEAD:       $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null) ($(git -C "$REPO" branch --show-current 2>/dev/null))"
    echo "dirty paths:    $(git -C "$REPO" status --porcelain 2>/dev/null | wc -l)"
    echo "binary sha256:  $(sha256sum "$BIN" 2>/dev/null | cut -c1-16)"
    echo
    echo "--- submodules ---"
    git -C "$REPO" submodule status 2>/dev/null
    echo
    echo "--- toolchain ---"
    clang --version 2>/dev/null | head -1
    ld.lld --version 2>/dev/null | head -1
    echo
    echo "--- graphics config ---"
    cat "$CONFIG_DIR/graphics.json" 2>/dev/null || echo "(no graphics.json yet)"
    echo "--- general config ---"
    cat "$CONFIG_DIR/general.json" 2>/dev/null
    echo
    echo "--- gpu state at launch ---"
    nvidia-smi --query-gpu=name,driver_version,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null \
        || echo "(nvidia-smi unavailable)"
    echo "vram consumers:"
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader 2>/dev/null | sed 's/^/  /'
    echo
    echo "--- vulkan layers / overlays in env (can hurt performance) ---"
    env | grep -i "^VK_\|^ENABLE_VULKAN\|MANGOHUD" || echo "  none"
    echo "======================================="
    echo
} >"$log_file" 2>&1

# keep only the newest $KEEP_LOGS runs
ls -1t "$LOG_DIR"/dk64-*.log 2>/dev/null | tail -n +$((KEEP_LOGS + 1)) | xargs -r rm -f --

stdbuf -o0 -e0 "$BIN" >>"$log_file" 2>&1
status=$?

{
    echo
    echo "===== exited ====="
    echo "exit code: $status"
    echo "ended:     $(date -Is)"
} >>"$log_file" 2>&1

echo "log: $log_file" >&2
exit $status
