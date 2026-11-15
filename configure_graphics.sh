#!/usr/bin/env bash
#
# Applies a graphics profile to ~/.config/DK64Recompiled/graphics.json, backing up
# whatever was there first. Idempotent and reversible.
#
#   ./configure_graphics.sh                 apply the "max" profile
#   ./configure_graphics.sh supersample     render ~2730x1920, present supersampled 480p
#   ./configure_graphics.sh retro240        render ~1440 high, present supersampled 240p
#   ./configure_graphics.sh vanilla         upstream defaults
#   ./configure_graphics.sh --check         show current values and available profiles
#   ./configure_graphics.sh --list          list backups
#   ./configure_graphics.sh --restore FILE  restore a specific backup
#
# Why "max" is the default: with res_option Auto, RT64 computes
# resolutionMultiplier = ceil(window_height / 240), so a 3440x1440 window renders at
# roughly 3440x1440. "Original 2x" plus 4x downsampling renders at 8x but then presents
# a 480-line image upscaled 3x, which is softer at this resolution while costing more
# VRAM. Use "supersample" for the deliberately smooth retro look, not for sharpness.
#
# Not part of the upstream project; see CONTRIBUTING.md before proposing it anywhere.

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/DK64Recompiled"
CONFIG_FILE="$CONFIG_DIR/graphics.json"
BACKUP_DIR="$CONFIG_DIR/graphics-backups"
KEEP_BACKUPS=20
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROFILE="max"
ACTION="apply"
RESTORE_FILE=""

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --check) ACTION="check"; shift ;;
        --list) ACTION="list"; shift ;;
        --restore) ACTION="restore"; RESTORE_FILE="$2"; shift 2 ;;
        max|supersample|retro240|vanilla) PROFILE="$1"; shift ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done

profiles_py() {
    cat <<'PY'
profiles = {
    # Sharpness-first: RT64 renders at the window resolution.
    "max": {
        "api_option": "Auto",
        "res_option": "Auto",
        "ds_option": 0,
        "msaa_option": "MSAA4X",
        "hpfb_option": "On",
        "draw_distance": 100,
        "ar_option": "Expand",
        "hr_option": "Clamp16x9",
        "rr_option": "Display",
        "rr_manual_value": 144,
        "wm_option": "Fullscreen",
        "cutscene_borders": "On",
        "developer_mode": False,
    },
    # Render ~2730x1920, present supersampled 480p: smooth, softer, more VRAM.
    "supersample": {
        "res_option": "Original2x",
        "ds_option": 4,
        "msaa_option": "MSAA4X",
        "hpfb_option": "On",
        "draw_distance": 100,
    },
    # Render ~1440 high, present supersampled 240p: purist retro, cheapest of the two.
    "retro240": {
        "res_option": "Original",
        "ds_option": 4,
        "msaa_option": "MSAA4X",
        "hpfb_option": "On",
        "draw_distance": 100,
    },
    # Upstream defaults, as a fresh install would have them.
    "vanilla": {
        "api_option": "Auto",
        "res_option": "Auto",
        "ds_option": 0,
        "msaa_option": "MSAA2X",
        "hpfb_option": "Off",
        "draw_distance": 0,
        "ar_option": "Expand",
        "hr_option": "Clamp16x9",
        "rr_option": "Display",
        "rr_manual_value": 60,
        "wm_option": "Windowed",
        "cutscene_borders": "On",
        "developer_mode": False,
    },
}
known_keys = [
    "api_option", "res_option", "ds_option", "msaa_option", "hpfb_option",
    "draw_distance", "ar_option", "hr_option", "rr_option", "rr_manual_value",
    "wm_option", "cutscene_borders", "developer_mode",
]
PY
}

show_current() {
    [[ -f "$CONFIG_FILE" ]] || { echo "no config yet at $CONFIG_FILE"; return; }
    python3 - "$CONFIG_FILE" <<'PY'
import json,sys
cfg=json.load(open(sys.argv[1]))
for k in sorted(cfg):
    print(f"  {k:20s} {cfg[k]}")
PY
}

case "$ACTION" in
    check)
        echo "current ($CONFIG_FILE):"
        show_current
        echo
        echo "profiles: max (default), supersample, retro240, vanilla"
        echo "backups:  $BACKUP_DIR"
        exit 0
        ;;
    list)
        ls -1t "$BACKUP_DIR"/graphics-*.json 2>/dev/null | head -"$KEEP_BACKUPS" || echo "no backups yet"
        exit 0
        ;;
    restore)
        [[ -f "$RESTORE_FILE" ]] || { echo "no such file: $RESTORE_FILE" >&2; exit 1; }
        mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"
        if [[ -f "$CONFIG_FILE" ]]; then
            cp -f "$CONFIG_FILE" "$BACKUP_DIR/graphics-before-restore-$(date +%Y%m%d-%H%M%S).json"
        fi
        cp -f "$RESTORE_FILE" "$CONFIG_FILE"
        echo "restored $RESTORE_FILE -> $CONFIG_FILE"
        show_current
        exit 0
        ;;
esac

if pgrep -x DK64Recompiled >/dev/null 2>&1; then
    echo "DK64Recompiled is running and rewrites graphics.json on exit." >&2
    echo "Close the game first, then run this again." >&2
    exit 1
fi

mkdir -p "$CONFIG_DIR" "$BACKUP_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
    backup="$BACKUP_DIR/graphics-$(date +%Y%m%d-%H%M%S).json"
    cp -f "$CONFIG_FILE" "$backup"
    echo "backed up: $backup"
    ls -1t "$BACKUP_DIR"/graphics-*.json 2>/dev/null | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f --
else
    echo "no existing config; a default one will be created"
fi

previous="$(mktemp)"
current="$(mktemp)"
previous_pretty="$previous.pretty"
current_pretty="$current.pretty"
trap 'rm -f "$previous" "$current" "$previous_pretty" "$current_pretty"' EXIT
[[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$previous" || echo '{}' >"$previous"

python3 - "$CONFIG_FILE" "$previous" "$current" "$PROFILE" <<PY
import json, sys
$(profiles_py)
config_path, previous_path, current_path, profile_name = sys.argv[1:5]

try:
    current = json.load(open(previous_path))
except Exception:
    current = {}

profile = profiles[profile_name]
unknown = [k for k in profile if k not in known_keys]
if unknown:
    raise SystemExit(f"profile {profile_name} has unknown keys: {unknown}")

for key, value in profile.items():
    if key in current or key in known_keys:
        current[key] = value

for key in sorted(current):
    if key not in known_keys:
        print(f"warning: keeping unrecognised key '{key}' (added by a newer upstream build?)",
              file=sys.stderr)

with open(config_path, "w") as fh:
    json.dump(current, fh, indent=4)
    fh.write("\n")
PY

echo "applied profile: $PROFILE"
echo
echo "changes:"
python3 -m json.tool "$previous" >"$previous_pretty" 2>/dev/null || cp "$previous" "$previous_pretty"
python3 -m json.tool "$CONFIG_FILE" >"$current_pretty" 2>/dev/null || cp "$CONFIG_FILE" "$current_pretty"
# Capture the diff instead of testing it in a pipeline: diff exits 1 when files
# differ, and `set -o pipefail` would otherwise turn that into a false negative.
diff_out="$( { diff -u "$previous_pretty" "$current_pretty" || true; } | sed '1,2d')"
if [[ -n "$diff_out" ]]; then
    printf '%s\n' "$diff_out"
else
    echo "  (nothing changed)"
fi
echo
show_current
cat <<EOF

Notes
  - resolution, msaa, downsampling and window mode are read at startup: restart the game.
  - draw_distance is re-read every frame, so it applies live.
  - downsampling (ds_option 2 or 4) is only used with res_option Original/Original2x;
    with Auto it is ignored, which is why the "max" profile sets it to 0.
  - Original 2x + 4x renders at roughly 2730x1920 and needs several GB of free VRAM:
    close anything else holding VRAM (an inference engine, for example) before using it.
  - undo: ./configure_graphics.sh --restore \$(ls -1t $BACKUP_DIR/graphics-*.json | head -1)
  - repo: $REPO_DIR
EOF
