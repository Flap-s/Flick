#!/bin/zsh
# Packs Flick.app into a disk image whose window invites dragging the app onto the Applications folder.
# Usage: Scripts/make-dmg.sh path/to/Flick.app path/to/Flick.dmg
#
# The window layout is set by asking Finder, which macOS may first ask you to allow (Automation). If Finder can't be
# driven, the image still works: it just opens without the background and arranged icons.
set -euo pipefail

APP="${1:?usage: make-dmg.sh Flick.app Flick.dmg}"
OUT="${2:?usage: make-dmg.sh Flick.app Flick.dmg}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VOLNAME="Flick"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/flick-dmg.XXXXXX")"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" && -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -force -quiet || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# Another "Flick" volume would make Finder lay out the wrong window.
for vol in /Volumes/"$VOLNAME"*(N); do hdiutil detach "$vol" -force -quiet || true; done

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Flick.app"
ln -s /Applications "$STAGE/Applications"
swift "$ROOT/Scripts/make-dmg-background.swift" "$STAGE/.background/background.png"

hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"

if osascript <<OSA 2>/dev/null
tell application "Finder"
  set theDisk to (disk "$VOLNAME")
  open theDisk
  set theWindow to container window of theDisk
  set current view of theWindow to icon view
  set toolbar visible of theWindow to false
  set statusbar visible of theWindow to false
  try
    set pathbar visible of theWindow to false
  end try
  try
    set extension hidden of item "Flick.app" of theDisk to true
  end try
  set bounds of theWindow to {200, 120, 840, 548}
  set options to icon view options of theWindow
  set arrangement of options to not arranged
  set icon size of options to 112
  set text size of options to 13
  set background picture of options to file ".background:background.png" of theDisk
  set position of item "Flick.app" of theWindow to {170, 200}
  set position of item "Applications" of theWindow to {470, 200}
  update theDisk without registering applications
  delay 1
  close theWindow
end tell
OSA
then
  echo "Disk image window laid out."
else
  echo "warning: Finder couldn't lay out the window (Automation not allowed?); the image works but looks plain." >&2
fi
# The volume's own icon. Added last: hdiutil leaves it out of -srcfolder and Finder drops it while laying out.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o "$OUT"
echo "Built $OUT"
