# DisableSinglePlayer

*Removes solo play from Slay the Spire 2.*

[![Latest release](https://img.shields.io/github/v/release/callistachang/STSDisableSingleplayer)](https://github.com/callistachang/STSDisableSingleplayer/releases/latest)

A mod for [**Slay the Spire 2**](https://store.steampowered.com/app/2868840/Slay_the_Spire_2/)
that takes singleplayer off the table: the Singleplayer main menu entry is hidden, and
every code path that starts or resumes a solo run is refused. 

Windows, Linux, and macOS. Tested against STS2 `v0.109.1`.

## For Players

### 1. Install the Mod

Download the latest `DisableSinglePlayer-v*.zip` from
[**Releases**](https://github.com/callistachang/STSDisableSingleplayer/releases/latest)
and unzip it into the game's mods directory. The archive already contains the correctly
named `DisableSinglePlayer` folder, so it lands in the right place.

One build covers every platform — only the mods directory differs:

| Platform | Mods directory |
|---|---|
| Windows | `<install>\mods\` |
| Linux | `<install>/mods/` |
| macOS | `<install>/SlayTheSpire2.app/Contents/MacOS/mods/` |

`<install>` is your Steam install root - the folder containing `SlayTheSpire2.exe`, or
`SlayTheSpire2.app` on macOS. Create `mods` if it isn't there.

Placing the two files by hand works just as well — that's all the zip contains. e.g. from
a terminal on macOS:

```sh
MODS="$GAME/SlayTheSpire2.app/Contents/MacOS/mods/DisableSinglePlayer"
mkdir -p "$MODS"
cp DisableSinglePlayer.dll DisableSinglePlayer.json "$MODS/"
```

### 2. Verify It Loaded

Every action logs with a `[DisableSinglePlayer]` tag.

```powershell
Get-ChildItem "$env:APPDATA\SlayTheSpire2\logs" | Sort-Object LastWriteTime |
  Select-Object -Last 1 | Get-Content | Select-String "DisableSinglePlayer"
```

```sh
# macOS; on Linux use ~/.local/share/SlayTheSpire2/logs
LOGS="$HOME/Library/Application Support/SlayTheSpire2/logs"
grep -i "DisableSinglePlayer" "$LOGS/$(ls -1t "$LOGS" | head -1)"
```

A healthy startup reports one `patched …` line per target plus
`hid the Singleplayer main menu entry.` A `MISSING:` line means a game update renamed
something. No tagged lines at all means the loader never found the mod; re-check step 1.

### What changes

- The Singleplayer main menu entry is gone.
- Any remaining route into a solo run - including a controller shortcut - become no-ops.
- Existing solo saves become unloadable. Continue may still appear and do nothing.

## For Developers

### Build & Install

Needs the **.NET 9 SDK**.

- **Windows** — [installer](https://dotnet.microsoft.com/download/dotnet/9.0), or
  `winget install Microsoft.DotNet.SDK.9`
- **macOS / Linux** — `curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0`
  installs to `~/.dotnet` without touching the global `PATH`; `build.sh` picks it up from
  there automatically.

Then:

```powershell
.\build.ps1             # Windows: build + copy into the game's mods folder
.\build.ps1 -BuildOnly  # build only
```

```sh
./build.sh              # macOS, Linux: build + copy into the game's mods folder
./build.sh --build      # build only
```

Both scripts find the Steam install themselves, including games on a non-default library
folder — they read `steamapps/libraryfolders.vdf` rather than assuming the default drive.
If autodetection misses, pass the install root:

```powershell
.\build.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Slay the Spire 2"
```

```sh
STS2_GAME_DIR="/mnt/games/SteamLibrary/steamapps/common/Slay the Spire 2" ./build.sh
```

`build.sh` also takes `DATA_DIR` and `MODS_DIR` to override the derived paths
individually; `build.ps1` takes `-ModsDir`.

Building without the scripts works too - the `.csproj` probes the default Steam location
for each platform, which is what makes opening the project in an IDE work:

```sh
dotnet build -c Release -p:STS2GameDir="<install root>"
```

### Cutting a Release

```sh
./release.sh 1.1.0      # bump the manifest, build, package, tag, publish
./release.sh            # release the version already in the manifest
./release.sh --dry-run  # build dist/DisableSinglePlayer-v*.zip and stop
```

`DisableSinglePlayer.json` holds the version — the `.csproj` has none — and the tag is
that version prefixed with `v`. The zip nests the DLL and the manifest under a
`DisableSinglePlayer/` folder so players can unzip straight into `mods/`. One archive
covers all three platforms, since the output is platform-agnostic IL.

Releases are cut locally, not in CI. The `.csproj` references `sts2.dll` and
`GodotSharp.dll` from a Steam install, so only a machine that owns the game can build the
mod, and vendoring those assemblies to satisfy a runner would mean redistributing them.

Note the release notes quote the "Tested against STS2" version from the top of this file —
re-verify against the current game build and update that line before releasing.