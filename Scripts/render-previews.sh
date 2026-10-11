#!/bin/bash
# 编译独立的视图渲染程序；窗口离屏且使用示例数据，产物写入 Artifacts。
set -eu
repo_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage_directory=$(mktemp -d "$repo_directory/build/.previews-XXXXXX")
trap 'rm -rf "$stage_directory"' EXIT
application="$stage_directory/TaskEasePreview.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
cp "$repo_directory/build/TaskEase.app/Contents/Resources/Assets.car" "$application/Contents/Resources/"
cp "$repo_directory/TaskEase/Resources/PostHog.json" "$application/Contents/Resources/"
cp "$repo_directory/build/TaskEase.app/Contents/Info.plist" "$application/Contents/Info.plist"
/usr/libexec/PlistBuddy \
    -c 'Set :CFBundleIdentifier com.github.polang233.TaskEase.PreviewRenderer' \
    -c 'Set :CFBundleExecutable TaskEasePreview' "$application/Contents/Info.plist"
sources=()
while IFS= read -r source; do
    case "$source" in */TaskEaseApp.swift) continue ;; esac
    sources+=("$source")
done < <(rg --files "$repo_directory/TaskEase" -g '*.swift')
xcrun clang -target arm64-apple-macos14.0 -c \
    "$repo_directory/TaskEase/Services/ProcessControl/ProcessBridge.c" \
    -o "$stage_directory/ProcessBridge.o"
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos14.0 \
    -module-cache-path "$stage_directory/ModuleCache" \
    -import-objc-header "$repo_directory/TaskEase/Services/ProcessControl/TaskEase-Bridging-Header.h" \
    -framework IOKit "$stage_directory/ProcessBridge.o" \
    "${sources[@]}" "$repo_directory/Scripts/render-previews.swift" \
    -o "$application/Contents/MacOS/TaskEasePreview"
"$application/Contents/MacOS/TaskEasePreview" "$repo_directory/Artifacts"
