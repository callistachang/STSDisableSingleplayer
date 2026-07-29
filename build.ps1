<#
.SYNOPSIS
    Build DisableSinglePlayer and install it into the game's mods folder.

.DESCRIPTION
    The Windows counterpart to build.sh. The compiled DLL is a platform-agnostic
    .NET assembly -- it is byte-identical to a macOS or Linux build; only the
    paths differ.

    The Steam install is found automatically via the registry and
    libraryfolders.vdf, so a game on a second drive is picked up without
    configuration. Override with -GameDir or $env:STS2_GAME_DIR.

.PARAMETER GameDir
    Slay the Spire 2 install root (the folder containing SlayTheSpire2.exe).
    Falls back to $env:STS2_GAME_DIR, then to autodetection.

.PARAMETER ModsDir
    Where to install. Defaults to <GameDir>\mods.

.PARAMETER BuildOnly
    Compile without installing.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Slay the Spire 2"
    .\build.ps1 -BuildOnly
#>
param(
    [string]$GameDir,
    [string]$ModsDir,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
$ModId = "DisableSinglePlayer"

Set-Location $PSScriptRoot

# --- locating the game -------------------------------------------------------

# Steam records extra library folders in libraryfolders.vdf, so the game is
# frequently not under the Steam root itself (second drive, external disk).
function Get-SteamLibraries {
    $roots = @()

    foreach ($key in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
                       "HKLM:\SOFTWARE\Valve\Steam",
                       "HKCU:\SOFTWARE\Valve\Steam")) {
        $path = (Get-ItemProperty -Path $key -Name InstallPath -ErrorAction SilentlyContinue).InstallPath
        if ($path) { $roots += $path }
    }
    $roots += "${env:ProgramFiles(x86)}\Steam"
    $roots += "$env:ProgramFiles\Steam"

    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path $root)) { continue }
        $root

        # Paths in the .vdf are C-escaped ("D:\\SteamLibrary"), hence the unescape.
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' -AllMatches |
                ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
        }
    }
}

function Find-GameDir {
    foreach ($lib in Get-SteamLibraries) {
        $candidate = Join-Path $lib "steamapps\common\Slay the Spire 2"
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

if (-not $GameDir) { $GameDir = $env:STS2_GAME_DIR }
if (-not $GameDir) { $GameDir = Find-GameDir }

if (-not $GameDir -or -not (Test-Path $GameDir)) {
    Write-Host @"
ERROR: could not find the Slay the Spire 2 install.

Point it at the folder containing SlayTheSpire2.exe:
  .\build.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Slay the Spire 2"

Or set it once in your PowerShell profile:
  `$env:STS2_GAME_DIR = "D:\SteamLibrary\steamapps\common\Slay the Spire 2"
"@ -ForegroundColor Red
    exit 1
}

# The game ships one data_sts2_<platform>_<arch> folder per architecture it was
# exported for. sts2.dll is managed IL and identical across them, so the first
# one that exists is fine to compile against.
$dataDir = Get-ChildItem -Path $GameDir -Directory -Filter "data_sts2_*" -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "sts2.dll") } |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $dataDir) {
    Write-Host "ERROR: no data_sts2_* folder containing sts2.dll under '$GameDir'." -ForegroundColor Red
    Write-Host "Make sure -GameDir points at the install root, not the Steam library root." -ForegroundColor Red
    exit 1
}

# ModManager.Initialize does Path.Combine(Path.GetDirectoryName(OS.GetExecutablePath()), "mods").
# On Windows the executable sits at the install root, so mods\ does too.
if (-not $ModsDir) { $ModsDir = Join-Path $GameDir "mods" }

# --- toolchain ---------------------------------------------------------------

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host @"
ERROR: 'dotnet' not found.

Install the .NET 9 SDK from:
  https://dotnet.microsoft.com/download/dotnet/9.0
"@ -ForegroundColor Red
    exit 1
}

# --- build and install -------------------------------------------------------

Write-Host "==> game $GameDir"
Write-Host "==> data $dataDir"
dotnet build -c Release -p:STS2DataDir="$dataDir"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$dll = Join-Path $PSScriptRoot "bin\Release\net9.0\$ModId.dll"
if (-not (Test-Path $dll)) {
    Write-Host "ERROR: build produced no $dll" -ForegroundColor Red
    exit 1
}

if ($BuildOnly) {
    Write-Host "==> built $dll (not installed)"
    exit 0
}

$dest = Join-Path $ModsDir $ModId
Write-Host "==> installing to $dest"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item $dll (Join-Path $dest "$ModId.dll") -Force
Copy-Item (Join-Path $PSScriptRoot "$ModId.json") (Join-Path $dest "$ModId.json") -Force

Write-Host "==> installed:"
Get-ChildItem $dest | Format-Table Name, Length, LastWriteTime

Write-Host @"
Next: launch the game, then check the newest log for lines tagged [$ModId]:

  Get-ChildItem "`$env:APPDATA\SlayTheSpire2\logs" | Sort-Object LastWriteTime |
    Select-Object -Last 1 | Get-Content | Select-String "$ModId"

If nothing is tagged, the loader never found the mod -- see README.md, "1. Install the Mod".
"@
