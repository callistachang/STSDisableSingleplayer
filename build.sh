#!/usr/bin/env bash
# Build DisableSinglePlayer and install it into the game's mods folder.
#
#   ./build.sh            build + install
#   ./build.sh --build    build only
#
# macOS and Linux. On Windows use build.ps1 -- the compiled DLL is identical
# either way, only the paths differ.
#
# The Steam install is found automatically, including non-default library
# folders. Override with STS2_GAME_DIR, or set DATA_DIR / MODS_DIR directly if
# your layout is unusual.
set -euo pipefail

MOD_ID="DisableSinglePlayer"

cd "$(dirname "$0")"

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *) echo "error: unsupported platform '$(uname -s)'. Use build.ps1 on Windows." >&2; exit 1 ;;
esac

# --- locating the game -------------------------------------------------------

# Steam records extra library folders in libraryfolders.vdf, so the game is
# frequently not under the Steam root itself (second drive, external disk).
# Yields each Steam root followed by every library path it knows about.
steam_libraries() {
  local roots=() root vdf

  if [[ $PLATFORM == macos ]]; then
    roots=("$HOME/Library/Application Support/Steam")
  else
    roots=("$HOME/.steam/steam"
           "$HOME/.local/share/Steam"
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")
  fi

  for root in "${roots[@]}"; do
    [[ -d $root ]] || continue
    printf '%s\n' "$root"
    vdf="$root/steamapps/libraryfolders.vdf"
    [[ -f $vdf ]] && sed -n 's/.*"path"[[:space:]]*"\(.*\)".*/\1/p' "$vdf"
  done
}

find_game_dir() {
  local lib candidate
  while IFS= read -r lib; do
    candidate="$lib/steamapps/common/Slay the Spire 2"
    [[ -d $candidate ]] && { printf '%s\n' "$candidate"; return 0; }
  done < <(steam_libraries)
  return 1
}

# The game ships one data_sts2_<platform>_<arch> folder per architecture it was
# exported for (macOS carries both arm64 and x86_64). sts2.dll is managed IL and
# identical across them, so the first one that exists is fine to compile against.
find_data_dir() {
  local dir
  for dir in "$1"/data_sts2_*; do
    [[ -f "$dir/sts2.dll" ]] && { printf '%s\n' "$dir"; return 0; }
  done
  return 1
}

STS2_GAME_DIR="${STS2_GAME_DIR:-$(find_game_dir || true)}"

if [[ -z ${STS2_GAME_DIR:-} || ! -d $STS2_GAME_DIR ]]; then
  echo "error: could not find the Slay the Spire 2 install." >&2
  echo "Point STS2_GAME_DIR at it, e.g.:" >&2
  if [[ $PLATFORM == macos ]]; then
    echo "  STS2_GAME_DIR=\"\$HOME/Library/Application Support/Steam/steamapps/common/Slay the Spire 2\" ./build.sh" >&2
  else
    echo "  STS2_GAME_DIR=\"\$HOME/.steam/steam/steamapps/common/Slay the Spire 2\" ./build.sh" >&2
  fi
  exit 1
fi

if [[ $PLATFORM == macos ]]; then
  APP="$STS2_GAME_DIR/SlayTheSpire2.app"
  # ModManager.Initialize does Path.Combine(Path.GetDirectoryName(OS.GetExecutablePath()), "mods").
  # On macOS the executable is Contents/MacOS/<binary>, so the mods folder sits in
  # Contents/MacOS -- NOT next to the .pck in Contents/Resources.
  MODS_DIR="${MODS_DIR:-$APP/Contents/MacOS/mods}"
  DATA_DIR="${DATA_DIR:-$(find_data_dir "$APP/Contents/Resources" || true)}"
else
  # On Linux and Windows the executable sits at the install root, so mods/ does too.
  MODS_DIR="${MODS_DIR:-$STS2_GAME_DIR/mods}"
  DATA_DIR="${DATA_DIR:-$(find_data_dir "$STS2_GAME_DIR" || true)}"
fi

if [[ -z ${DATA_DIR:-} || ! -f "$DATA_DIR/sts2.dll" ]]; then
  echo "error: sts2.dll not found under: $STS2_GAME_DIR" >&2
  echo "Set DATA_DIR to the data_sts2_* folder that contains it." >&2
  exit 1
fi

# --- toolchain ---------------------------------------------------------------

# The SDK may live in ~/.dotnet (installed via dot.net/v1/dotnet-install.sh -- the
# Homebrew cask needs sudo, this doesn't). Add it if it isn't already on PATH.
if ! command -v dotnet >/dev/null 2>&1 && [[ -x "$HOME/.dotnet/dotnet" ]]; then
  export PATH="$HOME/.dotnet:$PATH"
  export DOTNET_ROOT="$HOME/.dotnet"
fi

if ! command -v dotnet >/dev/null 2>&1; then
  echo "error: dotnet not found. Install the .NET 9 SDK:" >&2
  echo "  curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 9.0" >&2
  exit 1
fi

# --- build and install -------------------------------------------------------

echo "==> game $STS2_GAME_DIR"
echo "==> data $DATA_DIR"
dotnet build -c Release -p:STS2DataDir="$DATA_DIR"

DLL="bin/Release/net9.0/$MOD_ID.dll"
[[ -f $DLL ]] || { echo "error: build produced no $DLL" >&2; exit 1; }

if [[ ${1:-} == "--build" ]]; then
  echo "==> built $DLL (not installed)"
  exit 0
fi

DEST="$MODS_DIR/$MOD_ID"
echo "==> installing to $DEST"
mkdir -p "$DEST"
cp "$DLL" "$DEST/$MOD_ID.dll"
cp "$MOD_ID.json" "$DEST/$MOD_ID.json"

echo "==> installed:"
ls -l "$DEST"

if [[ $PLATFORM == macos ]]; then
  LOGS="\$HOME/Library/Application Support/SlayTheSpire2/logs"
else
  LOGS="\$HOME/.local/share/SlayTheSpire2/logs"
fi

cat <<EOF

Next: launch the game, then check the log for lines tagged [$MOD_ID]:

  ls -1t "$LOGS" | head -1

If nothing is tagged, the loader never found the mod -- see README.md, "1. Install the Mod".
EOF
