#!/bin/zsh
# Packs the signed release app into a drag-to-install disk image at dist/NTFSSilicon.dmg.
# Builds first (same signing as ./build.sh), stages app + /Applications symlink,
# then verifies the result: attach, codesign --verify, detach.
set -euo pipefail
here=$(dirname "$0")/..
name="NTFSSilicon"
app="$HOME/Applications/$name.app"

"$here/build.sh" "$@"

staging=$(mktemp -d /tmp/$name.dmg.XXXXXX)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/$name.app"
ln -s /Applications "$staging/Applications"

mkdir -p "$here/dist"
out="$here/dist/$name.dmg"
rm -f "$out"
hdiutil create -volname "$name" -srcfolder "$staging" -ov -format UDZO "$out" >/dev/null

# Verify the image actually installs and the code is intact.
mnt="$staging/mnt"
mkdir -p "$mnt"
hdiutil attach "$out" -readonly -nobrowse -mountpoint "$mnt" >/dev/null
test -x "$mnt/$name.app/Contents/MacOS/$name"
codesign --verify --strict "$mnt/$name.app"
hdiutil detach "$mnt" >/dev/null
echo "DMG OK $out"
