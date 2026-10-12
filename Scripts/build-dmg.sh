#!/bin/sh
# 把 build/TaskEase.app 打包为带拖放提示背景的 DMG，输出 build/TaskEase-版本.dmg。先运行 build-app.sh。
set -eu
repo_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
application="$repo_directory/build/TaskEase.app"
test -d "$application" || { printf '%s\n' 'Run Scripts/build-app.sh first.' >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$application/Contents/Info.plist")
volume="轻程 TaskEase"
output="$repo_directory/build/TaskEase-$version.dmg"
stage=$(mktemp -d "$repo_directory/build/.dmg-XXXXXX")
mount_point=""
cleanup() {
    if test -n "$mount_point" && test -d "$mount_point"; then hdiutil detach "$mount_point" -quiet -force || true; fi
    rm -rf "$stage"
}
trap cleanup EXIT

mkdir -p "$stage/content/.background" "$stage/art"
/usr/bin/ditto "$application" "$stage/content/TaskEase.app"
ln -s /Applications "$stage/content/Applications"
xcrun swift "$repo_directory/Scripts/dmg-background.swift" "$stage/art"
tiffutil -cathidpicheck "$stage/art/background.png" "$stage/art/background@2x.png" -out "$stage/content/.background/background.tiff" >/dev/null 2>&1

hdiutil create -quiet -srcfolder "$stage/content" -volname "$volume" -fs HFS+ -format UDRW -ov "$stage/rw.dmg"
mount_point=$(hdiutil attach "$stage/rw.dmg" -readwrite -noverify -noautoopen 2>/dev/null | awk -F '\t' '/\/Volumes\// { print $NF; exit }')
test -d "$mount_point"

# Finder 记录窗口大小、图标位置和背景；需要允许终端控制 Finder。
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$(basename "$mount_point")"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 548}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "TaskEase.app" of container window to {160, 190}
        set position of item "Applications" of container window to {480, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
chflags hidden "$mount_point/.background"
rm -rf "$mount_point/.fseventsd"
sync
hdiutil detach "$mount_point" -quiet
mount_point=""
hdiutil convert "$stage/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -ov -o "$output"
hdiutil verify -quiet "$output"
printf '%s\n' "$output"
