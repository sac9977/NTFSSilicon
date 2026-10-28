#!/bin/zsh
# Packs the app into a drag-to-install disk image at dist/NTFSSilicon.dmg.
# Signing adapts to what exists in the keyring:
#   - Developer ID Application cert (+ NOTARY keychain profile): re-signs
#     with hardened runtime, notarizes, staples — a dmg other Macs open
#     without a Gatekeeper prompt.
#   - Apple Development cert only: packs a dmg signed for this Mac; other
#     Macs get a Gatekeeper prompt on first open.
# Verifies its own output: attach, codesign --verify, detach.
# One-time setup for the notarized path:
#   1) Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2) xcrun notarytool store-credentials NOTARY \
#        --apple-id you@example.com --team-id <teamid> --password <app-specific-password>
set -euo pipefail
here=$(dirname "$0")/..
name="NTFSSilicon"
app="$HOME/Applications/$name.app"

"$here/build.sh" "$@"

# Distribution signing (takes over from the dev-signed build when present).
devid=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
if [[ -n "$devid" ]]; then
  echo "distribution signing: $devid"
  codesign --force --options runtime --timestamp --sign "$devid" "$app"
fi

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
hdiutil detach "$mnt" >/dev/null 2>&1

# Notarize + staple when both the cert and the stored profile exist.
if [[ -n "$devid" ]] && xcrun notarytool history --keychain-profile NOTARY >/dev/null 2>&1; then
  xcrun notarytool submit "$out" --keychain-profile NOTARY --wait --timeout 60m
  xcrun stapler staple "$out"
  codesign --verify --strict --verbose=1 "$app"
  xcrun stapler validate "$out"   # authoritative check for dmg containers
  echo "notarized+stapled: $out"
fi

echo "DMG OK $out"
