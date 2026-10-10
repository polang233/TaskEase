#!/bin/sh
# Build the app used outside Xcode. Run from any directory.
set -eu
repo_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$repo_directory/build"
stage_directory=$(mktemp -d "$repo_directory/build/.release-XXXXXX")
destination="$repo_directory/build/TaskEase.app"
cleanup() {
    if test -d "$stage_directory/previous.app" && ! test -e "$destination"; then
        /bin/mv "$stage_directory/previous.app" "$destination"
    fi
    rm -rf "$stage_directory"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
log_path="$repo_directory/build/release-build.log"

if ! xcodebuild -project "$repo_directory/TaskEase.xcodeproj" -target TaskEase \
    -configuration Release -sdk macosx \
    SYMROOT="$stage_directory/Products" OBJROOT="$stage_directory/Intermediates" \
    build > "$log_path" 2>&1; then
    tail -60 "$log_path" >&2
    exit 1
fi

candidate="$stage_directory/Products/Release/TaskEase.app"
executable="$candidate/Contents/MacOS/TaskEase"
test -x "$executable"
test ! -e "$candidate/Contents/MacOS/TaskEase.debug.dylib"
test ! -e "$candidate/Contents/MacOS/__preview.dylib"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist")" = com.github.polang233.TaskEase
codesign --verify --deep --strict "$candidate"

if test -L "$destination"; then
    printf '%s\n' 'The application destination is a symbolic link; left intact.' >&2
    exit 1
fi
/usr/bin/ditto "$candidate" "$stage_directory/deliver.app"
codesign --verify --deep --strict "$stage_directory/deliver.app"
if test -e "$destination"; then
    test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" = com.github.polang233.TaskEase
    /bin/mv "$destination" "$stage_directory/previous.app"
fi
/bin/mv "$stage_directory/deliver.app" "$destination"
codesign --verify --deep --strict "$destination"
printf '%s\n' "$destination"
