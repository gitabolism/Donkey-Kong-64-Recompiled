---
description: "Update the fork from the newest upstream DK64: Recompiled release, rebuild, and smoke test"
---

Bring this fork up to date with upstream and verify the build still works end to end.
Target: $ARGUMENTS (if empty, use the newest upstream release tag; fall back to `upstream/main`).

Live state at invocation:

!`git remote -v`

!`git log --oneline -3`

!`git status --short`

!`git submodule status`

## Ground rules

- `origin` is the fork (`gitabolism/...`), `upstream` is `https://github.com/Rainchus/Donkey-Kong-64-Recompiled.git`. Add `upstream` if it is missing.
- Never `git push`, `git push --force`, or `git rebase` past a point others may have based work on without my explicit approval in this conversation.
- Never touch `~/.config/DK64Recompiled/saves/` or anything under `/data`. Ask before writing to any path outside the repo.
- Keep it local otherwise: this repo's CONTRIBUTING.md forbids AI-assisted contributions, so the local helper scripts (`arch_build.sh`, `dk64_launcher.sh`, `setup_desktop_entry.sh`) and the `.opencode/` files stay on the fork and must not be turned into an upstream PR.

## 1. Snapshot before changing anything

1. Record the current HEAD and the local-only commits: `git log --oneline upstream/main..HEAD` (expect the helper-script commits).
2. Create a rollback branch: `git branch pre-update-$(date +%Y%m%d)` and tell me its name.
3. Back up the tuned settings: `tar czf ~/.config/DK64Recompiled-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C ~/.config DK64Recompiled` (ask first, it writes outside the repo).

## 2. Fetch and assess the delta

`git fetch upstream --tags --prune`

Diff the current base against the target and summarise it as a table (commit count, files, risk). Call out explicitly when the target changes any of these, because each one changes how the local build must be done:

| Upstream change | What it means locally |
| --- | --- |
| `.gitmodules`, or any submodule SHA in `git ls-tree` | `git submodule update --init --recursive`, then check whether rt64/N64ModernRuntime/RecompFrontend APIs moved under us |
| `.github/workflows/validate.yml` inputs `N64RECOMP_COMMIT` / `SDL2_VERSION` | the recompiler version must be bumped too, otherwise recompiled code will not match the runtime: update `N64RECOMP_COMMIT` in `arch_build.sh`, re-clone/checkout in `build/N64Recomp-src`, and regenerate all recompiler output |
| `us.toml`, `patches.toml`, `n_aspMain.toml`, `DK64Syms/` | full recompile required, never just an incremental link |
| ROM revision support (`BUILDING.md` sha1, `src/main/main.cpp` `rom_hash`) | the existing `donkeykong64.decompressed.us.z64` may be invalid; verify the ROM we own still matches the supported sha1 before assuming `--skip-rom` is safe |
| `CMakeLists.txt`, `patches/Makefile` | re-run the CMake configure step; re-check whether `-include cstdint` is still needed and whether `--allow-multiple-definition` became necessary |
| option keys in `src/game/config.cpp` or `lib/RecompFrontend/recompui/src/config/` | diff against `~/.config/DK64Recompiled/graphics.json` and `general.json` and report renamed/removed/added options instead of silently losing the tuned values |
| our own helper scripts or the README section | expect rebase conflicts; resolve in favour of upstream and re-apply the local additions on top |

## 3. Move the fork

1. Rebase the local-only commits onto the target: `git rebase --onto <target> <old-base> main` (or `git rebase <target>` when the base is `upstream/main`).
2. Resolve conflicts, then `git submodule update --init --recursive` and confirm `git submodule status` shows no `+` or `-` prefixes.
3. Report the new HEAD and the exact list of local commits on top of upstream.

## 4. Rebuild

Run `./arch_build.sh --skip-rom` first (fast path). Use the full pipeline `DK64_ROM="/data/Torrents/Complete/N64/ROMS/Donkey Kong 64 (U) [!].z64" ./arch_build.sh` whenever the recompiler pin, the toml files, the symbol dumps or the supported ROM revision changed. Rebuild the MIPS patches with `make -C patches CC=clang LD=ld.lld` if only they changed.

Build failures: report the first real error, not the tail of the log, and compare against what upstream CI does in `.github/workflows/validate.yml` before patching anything.

## 5. Smoke test

1. `./dk64_launcher.sh` (or the installed `dk64-recompiled`) and let it reach the title screen.
2. Read `~/.local/state/DK64Recompiled/logs/latest.log`: check the header (git HEAD, submodule pins, config snapshot, GPU state) and then
   `grep -nE "RSP ucode|Unhandled|Failed to execute|exit code|assert" latest.log`.
   `exit_reason: 3` in `n_aspMain` means the wrong ROM was passed to the runtime, not a broken build.
3. Confirm the settings we tuned (draw distance, MSAA, high-precision framebuffer, refresh rate) survived the update.

## 6. Report and stop

Give me: the target tag/commit, a delta summary table, submodule and recompiler-pin changes, build result, smoke-test result, the list of files that differ from `origin`, and the rollback branch name. Then wait for my approval before pushing anything.

Note that fork CI will fail on push because `validate.yml` needs the `SECRET_NAME`/`SECRET_TOKEN`/`SECRET_ENCRYPTION` secrets the private ROM repo uses. That failure is expected and not caused by the update.
