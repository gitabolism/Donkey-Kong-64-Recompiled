#!/usr/bin/env bash
#
# Installs a menu entry + launcher wrapper for a local DK64: Recompiled build.
# Uses only freedesktop conventions, so it works on KDE, GNOME, XFCE, Hyprland
# launchers, etc. (KDE detail is limited to StartupWMClass window grouping and
# the right-click Actions, which other desktops simply ignore.)
#
#   ./setup_desktop_entry.sh              install / refresh
#   ./setup_desktop_entry.sh --uninstall  remove what was installed
#   ./setup_desktop_entry.sh --check      show what would be installed
#
# Options:
#   --bin-dir DIR   where the launcher wrapper goes (default: ~/.local/bin)
#   --app-id ID     .desktop file base name (default: dk64recompiled-local)
#   --name NAME     menu label (default: "Donkey Kong 64: Recompiled")
#   --no-icon       skip installing the icon
#
# NOTE FOR CONTRIBUTORS: this file, dk64_launcher.sh and arch_build.sh are local
# build/desktop helpers. The project's CONTRIBUTING.md rejects AI-assisted code,
# so do not propose them upstream.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
# Match the name of the entry upstream ships in .github/linux/DK64Recompiled.desktop.
APP_ID="DK64Recompiled"
APP_NAME="DK64Recompiled"
INSTALL_ICON=1
MODE="install"
APP_NAME_SET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
        --uninstall) MODE="uninstall"; shift ;;
        --check) MODE="check"; shift ;;
        --bin-dir) BIN_DIR="$2"; shift 2 ;;
        --app-id) APP_ID="$2"; shift 2 ;;
        --name) APP_NAME="$2"; APP_NAME_SET=1; shift 2 ;;
        --no-icon) INSTALL_ICON=0; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -x "$REPO_DIR/DK64Recompiled" ]]; then
    echo "warning: $REPO_DIR/DK64Recompiled is missing - build first with ./arch_build.sh" >&2
fi

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
LAUNCHER="$BIN_DIR/$APP_ID"
DESKTOP="$DESKTOP_DIR/$APP_ID.desktop"
ICON="$ICON_DIR/$APP_ID.svg"
REPO_HINT="$BIN_DIR/.dk64_repo"
WRAPPER_SRC="$REPO_DIR/dk64_launcher.sh"

step() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }

remove_all() {
    step "Removing"
    for f in "$LAUNCHER" "$DESKTOP" "$ICON" "$REPO_HINT"; do
        if [[ -e "$f" ]]; then rm -f "$f" && echo "  removed $f"; else echo "  not present: $f"; fi
    done
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true
}

show_plan() {
    step "Would install"
    cat <<EOF
  launcher : $LAUNCHER           (from $WRAPPER_SRC)
  menu     : $DESKTOP
             base: $REPO_DIR/.github/linux/$APP_ID.desktop
  icon     : $ICON               (from $REPO_DIR/icons/app.svg, matches Icon=$APP_ID)
  repo hint: $REPO_HINT          (tells the installed wrapper which repo to run)
  desktop  : ${XDG_CURRENT_DESKTOP:-unknown}
EOF
}

case "$MODE" in
    uninstall) remove_all; exit 0 ;;
    check) show_plan; exit 0 ;;
esac

[[ -f "$WRAPPER_SRC" ]] || { echo "missing $WRAPPER_SRC" >&2; exit 1; }

show_plan
mkdir -p "$BIN_DIR" "$DESKTOP_DIR"

step "Installing launcher wrapper"
install -m 0755 "$WRAPPER_SRC" "$LAUNCHER"
echo "  $LAUNCHER"
# The installed copy lives outside the repo, so point it back at this checkout.
printf '%s\n' "$REPO_DIR" >"$REPO_HINT"

step "Installing menu entry"
TEMPLATE="$REPO_DIR/.github/linux/$APP_ID.desktop"
if [[ -f "$TEMPLATE" ]]; then
    echo "  base: $TEMPLATE"
    echo "        (upstream ships this entry but no build step installs it, so its"
    echo "         relative Exec= never resolves; we keep its keys and fix Exec)"
    sed "s|^Exec=.*|Exec=$LAUNCHER|" "$TEMPLATE" >"$DESKTOP"
    [[ $APP_NAME_SET -eq 1 ]] && sed -i "s|^Name=.*|Name=$APP_NAME|" "$DESKTOP"
    grep -q '^Comment=' "$DESKTOP" || echo "Comment=Static recompilation of Donkey Kong 64 for PC." >>"$DESKTOP"
else
    echo "  note: $TEMPLATE not found, writing a standalone entry"
    cat >"$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME
GenericName=N64 static recompilation (local build)
Exec=$LAUNCHER
Icon=$APP_ID
Terminal=false
Categories=Game;Emulator;
EOF
fi

# Local conveniences are appended; upstream's own keys are left alone.
grep -q '^Keywords=' "$DESKTOP" || echo "Keywords=n64;dk64;donkey kong;recompiled;recomp;" >>"$DESKTOP"
grep -q '^StartupWMClass=' "$DESKTOP" || echo "StartupWMClass=DK64Recompiled" >>"$DESKTOP"
if ! grep -q '^Actions=' "$DESKTOP"; then
    cat >>"$DESKTOP" <<EOF
Actions=settings;logs;

[Desktop Action settings]
Name=Open settings folder
Exec=xdg-open ${XDG_CONFIG_HOME:-$HOME/.config}/DK64Recompiled

[Desktop Action logs]
Name=Open log folder
Exec=xdg-open ${XDG_STATE_HOME:-$HOME/.local/state}/DK64Recompiled/logs
EOF
fi
echo "  $DESKTOP"

if [[ $INSTALL_ICON -eq 1 && -f "$REPO_DIR/icons/app.svg" ]]; then
    step "Installing icon"
    mkdir -p "$ICON_DIR"
    install -m 0644 "$REPO_DIR/icons/app.svg" "$ICON"
    echo "  $ICON"
fi

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true

if command -v desktop-file-validate >/dev/null 2>&1; then
    step "Validating"
    desktop-file-validate "$DESKTOP" && echo "  desktop entry OK"
else
    echo "note: desktop-file-validate not installed; skipped validation"
fi

step "Verifying the installed wrapper"
"$LAUNCHER" --check

cat <<EOF

Done.
  Menu: search for "${APP_NAME}" (${XDG_CURRENT_DESKTOP:-your desktop} may need a moment
        or a logout/login to refresh its app list).
  CLI : ${APP_ID}
  Logs: ${XDG_STATE_HOME:-$HOME/.local/state}/DK64Recompiled/logs/latest.log
  Remove again with: $REPO_DIR/setup_desktop_entry.sh --uninstall
EOF
