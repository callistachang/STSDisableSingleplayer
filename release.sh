#!/usr/bin/env bash
# Cut a GitHub release: bump, build, package, tag, publish.
#
#   ./release.sh              release the version already in DisableSinglePlayer.json
#   ./release.sh 1.1.0        bump the manifest to 1.1.0 first, then release
#   ./release.sh --dry-run    build and package only; touch nothing remote
#   ./release.sh --yes        skip the confirmation prompt
#
# The manifest is the single source of truth for the version -- the .csproj
# carries none -- and the git tag is that version with a `v` in front.
#
# There is deliberately no CI equivalent. The .csproj references sts2.dll and
# GodotSharp.dll out of a local Steam install, so a release can only be built on
# a machine that owns the game; vendoring those assemblies to make a runner work
# would mean redistributing them. Releases are cut from a developer's machine.
set -euo pipefail

MOD_ID="DisableSinglePlayer"

cd "$(dirname "$0")"

DRY_RUN=0
ASSUME_YES=0
NEW_VERSION=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown option '$arg'" >&2; exit 1 ;;
    *)
      [[ -n $NEW_VERSION ]] && { echo "error: more than one version given" >&2; exit 1; }
      NEW_VERSION="$arg"
      ;;
  esac
done

# --- version -----------------------------------------------------------------

# Plain sed rather than jq, which isn't installed by default anywhere we target.
# The quote before `version` is what keeps this off a future "min_game_version".
manifest_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MOD_ID.json" | head -1
}

if [[ -n $NEW_VERSION ]]; then
  [[ $NEW_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    { echo "error: version must look like 1.2.3, got '$NEW_VERSION'" >&2; exit 1; }
  VERSION="$NEW_VERSION"
else
  VERSION="$(manifest_version)"
  [[ -n $VERSION ]] ||
    { echo "error: no \"version\" found in $MOD_ID.json" >&2; exit 1; }
fi

TAG="v$VERSION"

# --- preflight ---------------------------------------------------------------

command -v zip >/dev/null 2>&1 ||
  { echo "error: zip not found. Install it, or package dist/$MOD_ID yourself." >&2; exit 1; }

if (( ! DRY_RUN )); then
  command -v gh >/dev/null 2>&1 ||
    { echo "error: gh not found. https://cli.github.com" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 ||
    { echo "error: gh is not authenticated. Run: gh auth login" >&2; exit 1; }

  # Untracked files are fine -- scratch notes live in this tree. Uncommitted
  # edits to tracked files are not: they'd ship in the tag but not the build.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "error: uncommitted changes to tracked files. Commit or stash first:" >&2
    git status --short --untracked-files=no >&2
    exit 1
  fi

  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "error: tag $TAG already exists locally. Bump the version, or delete it:" >&2
    echo "  git tag -d $TAG" >&2
    exit 1
  fi

  if git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists on origin. Bump the version." >&2
    exit 1
  fi
fi

# --- bump --------------------------------------------------------------------

BUMPED=0
if [[ -n $NEW_VERSION && $NEW_VERSION != "$(manifest_version)" ]]; then
  echo "==> bumping $MOD_ID.json to $VERSION"
  # A temp file rather than sed -i, whose syntax differs between BSD and GNU.
  sed 's/\("version"[[:space:]]*:[[:space:]]*"\)[^"]*"/\1'"$VERSION"'"/' \
    "$MOD_ID.json" > "$MOD_ID.json.tmp"
  mv "$MOD_ID.json.tmp" "$MOD_ID.json"
  [[ $(manifest_version) == "$VERSION" ]] ||
    { echo "error: bump did not take; check $MOD_ID.json by hand." >&2; exit 1; }
  BUMPED=1
fi

# --- build and package -------------------------------------------------------

# build.sh already knows how to find the Steam install and the .NET SDK.
echo "==> building"
./build.sh --build

DLL="bin/Release/net9.0/$MOD_ID.dll"
[[ -f $DLL ]] || { echo "error: build produced no $DLL" >&2; exit 1; }

# The mod output is platform-agnostic IL -- one zip serves Windows, Linux and
# macOS. It nests the two files under a $MOD_ID/ folder so that unzipping
# straight into the game's mods/ directory lands them where the loader looks.
ZIP="$MOD_ID-$TAG.zip"
STAGE="dist/$MOD_ID"

echo "==> packaging dist/$ZIP"
rm -rf "$STAGE" "dist/$ZIP"
mkdir -p "$STAGE"
cp "$DLL" "$STAGE/$MOD_ID.dll"
cp "$MOD_ID.json" "$STAGE/$MOD_ID.json"
( cd dist && zip -qr "$ZIP" "$MOD_ID" )
rm -rf "$STAGE"

unzip -l "dist/$ZIP"

if (( DRY_RUN )); then
  echo
  echo "==> dry run: dist/$ZIP built, nothing tagged or published."
  (( BUMPED )) && echo "    note: $MOD_ID.json was bumped to $VERSION and is uncommitted."
  exit 0
fi

# --- publish -----------------------------------------------------------------

# Which game build this was tested against is the fact players most need: the
# mod patches by reflection, so a renamed symbol upstream is the failure mode.
GAME_VERSION="$(sed -n 's/.*[Tt]ested against STS2 `\([^`]*\)`.*/\1/p' README.md | head -1)"

NOTES="Unzip into the game's \`mods\` folder -- the archive already contains the correctly-named \`$MOD_ID\` folder. See the README for the path on your platform."
[[ -n $GAME_VERSION ]] && NOTES="$NOTES"$'\n\n'"Tested against STS2 \`$GAME_VERSION\`."

echo
echo "About to publish:"
echo "  tag      $TAG"
echo "  asset    dist/$ZIP"
echo "  repo     $(gh repo view --json nameWithOwner -q .nameWithOwner)"
(( BUMPED )) && echo "  commit   $MOD_ID.json bump to $VERSION"

if (( ! ASSUME_YES )); then
  read -r -p "Publish? [y/N] " reply
  [[ $reply == [yY] ]] || { echo "aborted."; exit 1; }
fi

if (( BUMPED )); then
  git add "$MOD_ID.json"
  git commit -m "Release $TAG"
fi

git tag -a "$TAG" -m "$TAG"
git push origin HEAD
git push origin "$TAG"

# --generate-notes appends the commit log since the last release under ours.
gh release create "$TAG" "dist/$ZIP" \
  --title "$TAG" \
  --notes "$NOTES" \
  --generate-notes

echo
echo "==> released $TAG"
gh release view "$TAG" --web >/dev/null 2>&1 || true
