#!/usr/bin/env bash
#
# Full local build pipeline for Donkey Kong 64: Recompiled on Arch Linux / CachyOS.
# Companion to fedora_build.sh, but it also handles the steps that workflow only:
#   * fetching/building the N64Recomp + RSPRecomp tools
#   * decompressing the ROM (using decompressor.cpp)
#   * running the recompiler
#
# Usage:
#   ./arch_build.sh /path/to/"Donkey Kong 64 (U) [!].z64" [Debug]
#   DK64_ROM=/path/to/rom.z64 ./arch_build.sh
#
# Options:
#   Debug          build with CMAKE_BUILD_TYPE=Debug
#   --skip-tools   reuse the existing N64Recomp / RSPRecomp binaries
#   --skip-rom     reuse the existing decompressed ROM
#   --desktop      after building, run setup_desktop_entry.sh (writes into ~/.local,
#                  which is the only thing this script writes outside the repo)
#
# The input ROM must be the NTSC-U 1.0 release in .z64 (big endian) byte order.
# Nothing outside of this repository is written to unless --desktop is given.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# Keep in sync with the N64RECOMP_COMMIT input of .github/workflows/validate.yml and
# the commit pinned in flatpak/io.github.dk64recompiled.dk64recompiled.json.
N64RECOMP_REPO="https://github.com/N64Recomp/N64Recomp.git"
N64RECOMP_COMMIT="2b6f05688de2abc7d86da5b4a89b84c2c6acbabe"

# Expected hash of the input (compressed) ROM, see BUILDING.md.
ROM_SHA1="cf806ff2603640a748fca5026ded28802f1f4a50"
DECOMPRESSED_ROM="donkeykong64.decompressed.us.z64"

BUILD_TYPE="Release"
ROM_PATH="${DK64_ROM:-}"
SKIP_TOOLS=0
SKIP_ROM=0
DESKTOP_ENTRY=0

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        -d|Debug) BUILD_TYPE="Debug"; shift ;;
        --skip-tools) SKIP_TOOLS=1; shift ;;
        --skip-rom) SKIP_ROM=1; shift ;;
        --desktop) DESKTOP_ENTRY=1; shift ;;
        -*) echo "Unknown option: $1" >&2; usage 1 ;;
        *) ROM_PATH="$1"; shift ;;
    esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Toolchain check
# ---------------------------------------------------------------------------
step "Checking build dependencies"

MISSING=()
for tool in git cmake ninja clang clang++ ld.lld make python3 sha1sum; do
    command -v "$tool" >/dev/null 2>&1 || MISSING+=("$tool")
done

pkg_provides() {
    # Reports the pacman package owning the given file, if any.
    pacman -Qoq "$1" >/dev/null 2>&1
}

for header in /usr/include/SDL2/SDL.h /usr/include/X11/extensions/Xrandr.h \
              /usr/include/freetype2/ft2build.h /usr/include/zlib.h \
              /usr/include/curl/curl.h /usr/include/gtk-3.0/gtk/gtk.h; do
    [[ -e "$header" ]] || MISSING+=("$header (pacman package needed)")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    printf 'Missing:\n'
    printf '  - %s\n' "${MISSING[@]}"
    cat <<'EOF'

Install them with:
  sudo pacman -S --needed base-devel cmake ninja clang lld git python \
    sdl2 gtk3 freetype2 libx11 libxrandr zlib curl unzip
EOF
    fail "install the dependencies above and re-run"
fi

clang_major="$(clang -dumpversion | cut -d. -f1)"
if [[ "$clang_major" -lt 15 ]]; then
    fail "clang >= 15 is required (found $clang_major); the MIPS target is used to build the patches"
fi

# ---------------------------------------------------------------------------
# 1. Submodules
# ---------------------------------------------------------------------------
step "Initializing submodules"
git submodule update --init --recursive

# ---------------------------------------------------------------------------
# 2. N64Recomp + RSPRecomp
# ---------------------------------------------------------------------------
if [[ "$SKIP_TOOLS" -eq 0 || ! -x N64Recomp || ! -x RSPRecomp ]]; then
    step "Building N64Recomp and RSPRecomp"
    tools_src="build/N64Recomp-src"
    if [[ -d "$tools_src/.git" ]]; then
        git -C "$tools_src" fetch --quiet origin || true
    else
        git clone --quiet "$N64RECOMP_REPO" "$tools_src"
    fi
    git -C "$tools_src" checkout --quiet "$N64RECOMP_COMMIT"
    git -C "$tools_src" submodule update --init --recursive

    cmake -S "$tools_src" -B "$tools_src/cmake-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ >/dev/null
    cmake --build "$tools_src/cmake-build" --config Release --target N64RecompCLI RSPRecomp -j"$(nproc)"
    cp "$tools_src/cmake-build/N64Recomp" "$tools_src/cmake-build/RSPRecomp" .
else
    step "Reusing existing N64Recomp / RSPRecomp"
fi

[[ -x N64Recomp && -x RSPRecomp ]] || fail "N64Recomp / RSPRecomp missing"

# ---------------------------------------------------------------------------
# 3. Decompressed ROM
# ---------------------------------------------------------------------------
if [[ "$SKIP_ROM" -eq 0 ]]; then
    if [[ ! -f "$DECOMPRESSED_ROM" ]]; then
        [[ -n "$ROM_PATH" ]] || fail "no decompressed ROM found and no ROM given. Pass the path to the US .z64 ROM, or set DK64_ROM."
        [[ -f "$ROM_PATH" ]] || fail "ROM not found: $ROM_PATH"

        actual_sha1="$(sha1sum "$ROM_PATH" | cut -d' ' -f1)"
        if [[ "$actual_sha1" != "$ROM_SHA1" ]]; then
            fail "unexpected ROM: sha1 is $actual_sha1, expected $ROM_SHA1 (NTSC-U 1.0 .z64). This project only supports that revision."
        fi

        step "Decompressing ROM"
        mkdir -p build
        clang++ -O2 -std=c++17 decompressor.cpp -o build/decompressor $(pkg-config --cflags --libs zlib)
        ./build/decompressor "$ROM_PATH"
    else
        step "Reusing existing $DECOMPRESSED_ROM"
    fi
fi

[[ -f "$DECOMPRESSED_ROM" ]] || fail "$DECOMPRESSED_ROM is missing"

# ---------------------------------------------------------------------------
# 4. Recompilation
# ---------------------------------------------------------------------------
step "Recompiling the game (us.toml)"
./N64Recomp us.toml

step "Recompiling the RSP microcode (n_aspMain.toml)"
./RSPRecomp n_aspMain.toml

step "Building the patch elf (MIPS)"
make -C patches CC=clang LD=ld.lld

step "Recompiling the patches (patches.toml)"
./N64Recomp patches.toml

# ---------------------------------------------------------------------------
# 5. Native build
# ---------------------------------------------------------------------------
# "-include cstdint" is required because the vendored UI dependencies (RmlUi's
# robin_hood.h) rely on headers that libstdc++ no longer includes transitively.
# fedora_build.sh passes the same flag for the same reason.
step "Configuring CMake ($BUILD_TYPE)"
cmake -S . -B build-cmake -G Ninja -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DPATCHES_C_COMPILER=clang -DPATCHES_LD=ld.lld \
    -DCMAKE_CXX_FLAGS="-include cstdint"

step "Building DK64Recompiled"
cmake --build build-cmake --target DK64Recompiled -j"$(nproc)" --config "$BUILD_TYPE"

cp build-cmake/DK64Recompiled DK64Recompiled
chmod +x ./DK64Recompiled

step "Done"
cat <<EOF

Built: $REPO_DIR/DK64Recompiled

Run it from the repository root (it needs ./assets and ./recompcontrollerdb.txt):
  ./DK64Recompiled

The game itself expects the normal compressed ROM, not the decompressed one.
EOF

if [[ "$DESKTOP_ENTRY" -eq 1 ]]; then
    step "Installing menu entry and launcher"
    "$REPO_DIR/setup_desktop_entry.sh"
fi
