# NOTICE: the engine folder

This folder is a copy of the macOS engine from **GJ Materia** by Good JOE
(<https://github.com/goodjoeth/gj-materia>), taken at commit `2b58834f152e5bd61605daf96f9a9d9876895926`.
GJ Materia is the macOS port of **FF7Recomp** by bhuiyah (<https://github.com/bhuiyah/ff7-recomp-android>),
which statically recompiles FINAL FANTASY VII and renders it with **FFNx** (julianxhokaxhiu) on **bgfx**.
All of it is licensed under the **GNU General Public License v3.0** (see `LICENSE` in this folder), and
so is this folder. The copyright notices in each source file are unchanged.

## What was left out
GJ Materia's Android app, installer, documentation and images, test programs, README files, its app
icon and its SwiftUI launcher (its name and artwork are not part of the license grant). This folder keeps
the sources the macOS engine compiles, the build scripts, the patches, and the data tables under `config/`.

## What was changed here (GPL-3.0 section 5a)
- **The SwiftUI launcher was removed** (`src/mac/launcher/`, `src/mac/ff7_launcher_native.cpp`, and its
  7z/SwiftUI build inputs in `macos/CMakeLists.txt`). The engine app now has no user interface of its own: it
  starts the game at once and is driven by another program through environment variables
  (`FF7_GAME_DIR`, `FF7_HOME`, `FF7_QUICKBOOT=newgame|continue|resume`, `FF7_ASPECT`). What the launcher did
  for the player (writing `FFNx.toml` from settings, `mods/profile.xml`, `boosters.txt`, the
  `fixes/.../window.bin` file, staging the game folder) is now the caller's job. The achievements panel and
  booster icons that lived in the launcher's UI are gone.
- `src/mac/ff7_mac_main.mm`: the seven functions the launcher exported to the engine are gone or are
  no-ops; the app starts the game directly; closing the game window quits (it used to reopen the launcher).
  The window title, About panel and menus are renamed (the About panel credits GJ Materia and Good JOE).
- `macos/CMakeLists.txt`: the product is **NorthernCrater Engine** (`com.northerncrater.engine`); the app
  icon and the Swift language/SwiftUI linkage were removed.
- `tools/build_mac.sh`: product name and closing messages updated. `tools/make_installer.sh` and
  `tools/make_icon_mac.*` (GJ Materia's installer and icon) were removed.
- `patches/ffnx/0002-time-module-guest-addresses.patch` (new): FFNx's day/night time module reads its
  variables from game addresses given as hex strings; with the guest memory at an offset (arm64) they
  must go through `GPTR()`. Without it the game crashes as soon as a mod turns the time cycle on.

Everything else is as in the commit above. The third-party sources the build downloads (pcrecomp, FFNx,
bgfx, bx, bimg, SDL3, FFmpeg and others) are fetched at the commits pinned in `tools/setup_mac.sh` and
`tools/fetch_deps_mac.sh`; they keep their own licenses.

## Not affiliated
This project contains no game code or data and is not affiliated with or endorsed by Square Enix.
FINAL FANTASY is a trademark of Square Enix. The engine is built on your Mac from your own copy of the game;
do not share the built app, which contains code derived from the game.
- `src/mac/ff7_mac_main.mm`: `FF7_SWAP_AB=1` exchanges the controller's A and B buttons (the app's "swap confirm and cancel"; keyboard unaffected).
- `tools/ogg2wav.c` (new, NorthernCrater): decodes Ogg Vorbis to WAV with the libogg/libvorbis sources the build downloads; the app builds it on demand (`build_ogg2wav.sh`) to play mods' sound previews.
- `tools/hext_manifest.cpp`: defines a stub `g_mem_base`, so the build-time manifest tool links outside the game.
