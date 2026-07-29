# DisableSinglePlayer — "Co-op Only"

*Removes solo play from Slay the Spire 2. The Spire only opens for two.*

A mod for [**Slay the Spire 2**](https://store.steampowered.com/app/2868840/Slay_the_Spire_2/)
that takes singleplayer off the table: the Singleplayer main menu entry is hidden, and
every code path that starts or resumes a solo run is refused. Two layers, because hiding
a button is cosmetic — the enforcement is what makes it a rule.

Windows, Linux, and macOS. Tested against STS2 `v0.109.1`.

> [!caution]
> Running **any** mod makes the game switch to a separate modded save profile. Your
> Compendium and Timeline will look empty until you remove the mod. This is vanilla
> behaviour, not something this mod does — your real save is untouched. See
> [What changes](#what-changes).

> [!note]
> The DLL is a platform-agnostic .NET assembly — the same `DisableSinglePlayer.dll` and
> `DisableSinglePlayer.json` work on Windows, Linux, and macOS. No separate builds.

## For Players

### 1. Install the Mod

Put `DisableSinglePlayer.dll` and `DisableSinglePlayer.json` in a `DisableSinglePlayer`
folder inside the game's mods directory:

| Platform | Mods directory |
|---|---|
| Windows | `<install>\mods\` |
| Linux | `<install>/mods/` |
| macOS | `<install>/SlayTheSpire2.app/Contents/MacOS/mods/` |

`<install>` is your Steam install root — the folder containing `SlayTheSpire2.exe`, or
`SlayTheSpire2.app` on macOS. Create `mods` if it isn't there.

> [!warning]
> On macOS the mods folder is inside the app bundle, at `Contents/MacOS/mods/` — **not**
> `Contents/Resources/mods/`, which is what `<install>/mods/` looks like it means. The
> loader silently ignores the wrong one. Finder hides bundle contents, so right-click
> `SlayTheSpire2.app` → **Show Package Contents** → `Contents/MacOS`.

From a terminal on macOS:

```sh
GAME="$HOME/Library/Application Support/Steam/steamapps/common/Slay the Spire 2"
MODS="$GAME/SlayTheSpire2.app/Contents/MacOS/mods/DisableSinglePlayer"
mkdir -p "$MODS"
cp DisableSinglePlayer.dll DisableSinglePlayer.json "$MODS/"
```

### 2. Enable Mods

Launch the game. A consent dialog appears on first launch — accept it, or nothing loads.

The Modding settings screen only appears **after** at least one mod has been discovered,
so on a clean install there is no mods UI to find beforehand. Install first, then launch.

### 3. Verify It Loaded

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
something — see [DEVLOG.md](DEVLOG.md#what-to-re-check-after-a-game-update). No tagged
lines at all means the loader never found the mod; re-check step 1.

### What changes

- The Singleplayer main menu entry is gone.
- Any remaining route into a solo run — including a controller shortcut — no-ops.
- Existing solo saves become unloadable. Continue may still appear and do nothing.
- Compendium and Timeline disappear, because the game moves you to a modded save
  profile with no run history. Removing the mod restores everything.

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

Building without the scripts works too — the `.csproj` probes the default Steam location
for each platform, which is what makes opening the project in an IDE work:

```sh
dotnet build -c Release -p:STS2GameDir="<install root>"
```

### Layout

| File | Role |
|---|---|
| `DisableSinglePlayer.json` | Mod manifest. `id` must match the DLL filename. |
| `DisableSinglePlayer.csproj` | Targets `net9.0`, references the game's DLLs in place. |
| `src/ModEntry.cs` | `[ModInitializer]` entry point; applies the patches. |
| `src/SoloRunBlocker.cs` | Enforcement — refuses all solo run-start paths. |
| `src/MenuHider.cs` | Presentation — hides the Singleplayer menu entry. |
| `src/PatchUtil.cs` | Reflection + logging helpers that fail soft. |
| `build.sh` | Build and install — macOS, Linux. |
| `build.ps1` | Build and install — Windows. |

### How It Works

**Enforcement** (`SoloRunBlocker`) — five methods start or resume a solo run in v0.109.1.
All five get a Harmony prefix that skips the original. They're `async`, so the prefix
supplies a completed `Task` rather than leaving the caller a `null` to await.

**Presentation** (`MenuHider`) — postfixes on `NMainMenu._Ready` *and*
`NMainMenu.RefreshButtons` disable and hide the `_singleplayerButton` field.
`RefreshButtons` alone would put the button back after abandoning a run.

Nothing throws. Every lookup is allowed to fail and log `MISSING: …`, because this is an
Early Access target and a patch that throws inside `_Ready` leaves the player on a black
screen.

## Known Limitations

- **Refusal is silent.** Blocked run-starts log and no-op rather than showing a modal.
- **Existing solo saves become unloadable** rather than being hidden or migrated.
- **Windows and Linux are untested in-game.** No platform-specific code, and the install
  paths follow the layouts other STS2 mods use, but nobody has launched it on either.
- **Early Access churn.** Private fields like `_singleplayerButton` and async method names
  are not a stable API. Re-check after every game update.
