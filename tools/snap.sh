#!/bin/zsh
# Snapshots of every page in light and dark, rendered against a fixed
# synthetic volume fixture (no real names, sizes or devices ever appear).
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=volumes tools/snap.sh
set -u
app=~/Applications/NTFSSilicon.app/Contents/MacOS/NTFSSilicon
store=/tmp/NTFSSilicon-test.store
shots=/tmp/NTFSSilicon-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.saslu.ntfssilicon.savedState
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SNAPSHOT=$shots $app
