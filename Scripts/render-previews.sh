#!/bin/bash
# 编译独立的视图渲染程序；窗口短暂显示在屏幕上并截取自身合成图像，使用示例数据，产物写入 Artifacts。
set -eu
repo_directory=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination=${1:-"$repo_directory/Artifacts"}
mkdir -p "$destination"
stage_directory=$(mktemp -d "$repo_directory/build/.previews-XXXXXX")
trap 'rm -rf "$stage_directory"' EXIT
application="$stage_directory/TaskEasePreview.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"
cp "$repo_directory/build/TaskEase.app/Contents/Resources/Assets.car" "$application/Contents/Resources/"
cp "$repo_directory/build/TaskEase.app/Contents/Resources/AppIcon.icns" "$application/Contents/Resources/"
cp "$repo_directory/TaskEase/Resources/PostHog.json" "$application/Contents/Resources/"
cp "$repo_directory/build/TaskEase.app/Contents/Info.plist" "$application/Contents/Info.plist"
# 编译好的本地化资源来自 Release 包；PREVIEW_LANGUAGE 指定渲染语言，例如 en、zh-Hans、zh-Hant。
cp -R "$repo_directory/build/TaskEase.app/Contents/Resources/"*.lproj "$application/Contents/Resources/"
/usr/libexec/PlistBuddy \
    -c 'Set :CFBundleIdentifier com.github.polang233.TaskEase.PreviewRenderer' \
    -c 'Set :CFBundleExecutable TaskEasePreview' "$application/Contents/Info.plist"
sources=()
while IFS= read -r -d '' source; do
    case "$source" in */TaskEaseApp.swift) continue ;; esac
    sources+=("$source")
done < <(find "$repo_directory/TaskEase" -type f -name '*.swift' -print0)
objects=()
while IFS= read -r -d '' source; do
    object="$stage_directory/$(basename "$source" .c).o"
    xcrun clang -target arm64-apple-macos14.0 -c "$source" -o "$object"
    objects+=("$object")
done < <(find "$repo_directory/TaskEase" -type f -name '*.c' -print0)
xcrun swiftc -parse-as-library -swift-version 6 -target arm64-apple-macos14.0 \
    -module-cache-path "$stage_directory/ModuleCache" \
    -import-objc-header "$repo_directory/TaskEase/Services/ProcessControl/TaskEase-Bridging-Header.h" \
    -framework IOKit "${objects[@]}" \
    "${sources[@]}" "$repo_directory/Scripts/render-previews.swift" \
    -o "$application/Contents/MacOS/TaskEasePreview"
language=${PREVIEW_LANGUAGE:-zh-Hans}
"$application/Contents/MacOS/TaskEasePreview" "$destination" -AppleLanguages "($language)"
