#!/bin/sh
# 轻程一行安装：curl -fsSL https://raw.githubusercontent.com/polang233/TaskEase/main/Scripts/install.sh | sh
# 从 GitHub 最新发布下载 DMG，按发布页的 SHA-256 校验后安装到“应用程序”。curl 下载的文件不带隔离标记，
# 因此首次打开不会出现“无法验证开发者”的拦截。安装包下载到临时目录，隐藏挂载，结束或中断时自动卸载并删除。
# TASKEASE_INSTALL_DIR 可指定安装目录，TASKEASE_NO_OPEN=1 安装后不打开（用于测试）。
set -eu

repository=polang233/TaskEase
bundle_id=com.github.polang233.TaskEase
work=$(mktemp -d "${TMPDIR:-/tmp}/taskease-install.XXXXXX")
mount_point=""

cleanup() {
    if [ -n "$mount_point" ]; then
        hdiutil detach "$mount_point" -quiet 2>/dev/null || hdiutil detach "$mount_point" -quiet -force 2>/dev/null || true
    fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

fail() { printf '安装失败：%s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || fail "仅支持 macOS。"
[ "$(uname -m)" = arm64 ] || fail "轻程需要 Apple Silicon Mac。"
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "需要 macOS 14 或更高版本。"

printf '正在查询最新版本…\n'
curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repository/releases/latest" -o "$work/release.json" || fail "无法连接 GitHub。"

# 用系统自带的 JavaScript 解析发布信息，取版本号、DMG 地址和 GitHub 提供的 SHA-256。
release=$(osascript -l JavaScript - "$work/release.json" <<'JS'
function run(argv) {
    ObjC.import('Foundation')
    const text = $.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js
    const release = JSON.parse(text)
    const asset = (release.assets || []).find(item => item.name.toLowerCase().endsWith('.dmg'))
    return [release.tag_name || '', asset ? asset.browser_download_url : '',
            asset && asset.digest ? asset.digest.replace(/^sha256:/, '') : ''].join('\n')
}
JS
) || fail "无法读取发布信息。"
version=$(printf '%s\n' "$release" | sed -n 1p | sed 's/^[vV]//')
url=$(printf '%s\n' "$release" | sed -n 2p)
digest=$(printf '%s\n' "$release" | sed -n 3p)
[ -n "$version" ] && [ -n "$url" ] && [ -n "$digest" ] || fail "最新发布缺少安装包或校验信息。"

destination_dir=${TASKEASE_INSTALL_DIR:-/Applications}
if [ ! -w "$destination_dir" ]; then
    # 普通账户无法写入“应用程序”时，安装到自己的“应用程序”文件夹。
    destination_dir="$HOME/Applications"
    mkdir -p "$destination_dir"
fi
destination="$destination_dir/TaskEase.app"

if [ -d "$destination" ]; then
    installed=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist" 2>/dev/null || true)
    if [ "$installed" = "$version" ]; then
        printf '已是最新版本 %s：%s\n' "$version" "$destination"
        exit 0
    fi
fi

printf '正在下载轻程 %s…\n' "$version"
curl -fL --progress-bar "$url" -o "$work/TaskEase.dmg" || fail "下载失败。"
[ "$(shasum -a 256 "$work/TaskEase.dmg" | cut -d' ' -f1)" = "$digest" ] || fail "校验不一致，已停止安装。"
printf '校验通过。\n'

mount_point="$work/volume"
mkdir -p "$mount_point"
hdiutil attach "$work/TaskEase.dmg" -nobrowse -readonly -noautoopen -quiet -mountpoint "$mount_point" || fail "无法打开安装包。"
[ -d "$mount_point/TaskEase.app" ] || fail "安装包中没有找到轻程。"
packaged=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$mount_point/TaskEase.app/Contents/Info.plist" 2>/dev/null || true)
[ "$packaged" = "$bundle_id" ] || fail "安装包内容与预期不符。"

# 替换前结束正在运行的旧版本；控制进程发现主程序退出后会先恢复被限制的应用再退出。
running() { pgrep -f "$destination/Contents/MacOS/TaskEase" >/dev/null 2>&1; }
if running; then
    printf '正在退出旧版本…\n'
    # 只结束主程序；先结束控制进程会被主程序当作意外退出而重新启动。
    pkill -TERM -f "$destination/Contents/MacOS/TaskEase\$" 2>/dev/null || true
    waited=0
    while running && [ "$waited" -lt 15 ]; do sleep 1; waited=$((waited + 1)); done
    running && fail "旧版本仍在运行，请先退出轻程后重试。"
fi

ditto "$mount_point/TaskEase.app" "$work/TaskEase.app" || fail "无法复制应用。"
rm -rf "$destination"
mv "$work/TaskEase.app" "$destination" || fail "无法写入 $destination_dir。"
printf '已安装到 %s\n' "$destination"

if [ "${TASKEASE_NO_OPEN:-}" != 1 ]; then
    open "$destination"
fi
