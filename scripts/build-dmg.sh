#!/bin/bash
#
# 把 .app bundle 打成 DMG，用于 GitHub Release 分发。
#
# 用法：
#   ./scripts/build-dmg.sh path/to/CCStatus.app
#   ./scripts/build-dmg.sh path/to/CCStatus.app --output dist/
#   ./scripts/build-dmg.sh path/to/CCStatus.app --name CCStatus-custom
#
# 默认输出到项目根的 dist/ 目录。
# 默认 DMG 文件名 = <CFBundleName>-<version>-<arch>.dmg
#   - version 从 Info.plist 的 CFBundleShortVersionString 推断
#   - arch 从 lipo -info 推断
#
# 行为：
#   - 优先使用 brew install create-dmg 安装的 create-dmg
#     （能产出带 Applications 快捷方式的"标准"DMG）。
#   - 缺失则回退到 hdiutil（产物是纯压缩镜像，也能用）。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    sed -n '2,22p' "$0"
    exit 1
}

APP_PATH=""
OUTPUT_DIR=""
OUTPUT_NAME=""     # 自定义输出文件名（不含 .dmg 后缀）；空则用 .app basename
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|-o) OUTPUT_DIR="$2"; shift 2 ;;
        --output=*) OUTPUT_DIR="${1#*=}"; shift ;;
        --name|-n) OUTPUT_NAME="$2"; shift 2 ;;
        --name=*) OUTPUT_NAME="${1#*=}"; shift ;;
        -h|--help) usage ;;
        -*) echo "unknown arg: $1" >&2; usage ;;
        *)
            if [[ -z "$APP_PATH" ]]; then APP_PATH="$1"
            else echo "unexpected extra arg: $1" >&2; usage
            fi
            shift ;;
    esac
done

[[ -z "$APP_PATH" ]] && usage
[[ ! -d "$APP_PATH" ]] && { echo "error: $APP_PATH is not a directory" >&2; exit 1; }

APP_PATH="$(cd "$APP_PATH" && pwd)"
APP_NAME="$(basename "$APP_PATH" .app)"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0.0")"

# 提取 arch 标识：universal / arm64 / x86_64
BIN="$APP_PATH/Contents/MacOS/$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \
            "$APP_PATH/Contents/Info.plist")"
ARCH_LABEL=$(lipo -info "$BIN" 2>/dev/null \
    | sed -E 's/.*(arm64|x86_64|i386).*/\1/' \
    | tr '\n' '-' \
    | sed 's/-$//')
if [[ -z "$ARCH_LABEL" ]]; then ARCH_LABEL="unknown"; fi
if [[ "$ARCH_LABEL" == "arm64-x86_64" ]] || [[ "$ARCH_LABEL" == "x86_64-arm64" ]]; then
    ARCH_LABEL="universal"
fi

# 默认 DMG 输出到项目根的 dist/
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/dist}"
mkdir -p "$OUTPUT_DIR"

# 默认 DMG 文件名 = <AppName>-<version>-<arch>.dmg
# - AppName 来自 .app 的 CFBundleName（如果存在）或 basename
# - version 来自 CFBundleShortVersionString
# - arch 来自 lipo -info
# 自定义优先级：--name 完全覆盖
if [[ -z "$OUTPUT_NAME" ]]; then
    BUNDLE_DISPLAY_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" \
        "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "$APP_NAME")"
    OUTPUT_NAME="${BUNDLE_DISPLAY_NAME}-${VERSION}-${ARCH_LABEL}"
fi
DMG_NAME="$OUTPUT_NAME.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "==> Packaging $APP_PATH"
echo "    version : $VERSION"
echo "    arch    : $ARCH_LABEL"
echo "    output  : $DMG_PATH"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_PATH" "$STAGE_DIR/"

# 软链到 /Applications，方便用户拖拽
ln -s /Applications "$STAGE_DIR/Applications"

if command -v create-dmg >/dev/null 2>&1; then
    echo "==> create-dmg"
    # 允许覆盖已存在的 DMG
    rm -f "$DMG_PATH"
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 160 185 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 440 185 \
        --no-internet-enable \
        "$DMG_PATH" "$STAGE_DIR" \
        || {
            # create-dmg 在已有同名 dmg 时会非零退出；不算致命
            echo "    (create-dmg returned non-zero, falling through to hdiutil if needed)"
        }
    [[ -f "$DMG_PATH" ]] || {
        echo "==> Falling back to hdiutil"
        rm -f "$DMG_PATH"
        hdiutil create -volname "$APP_NAME" \
            -srcfolder "$STAGE_DIR" \
            -ov -format UDZO \
            "$DMG_PATH"
    }
else
    echo "==> create-dmg not found; using hdiutil"
    echo "    (install with: brew install create-dmg  for nicer DMG UX)"
    rm -f "$DMG_PATH"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGE_DIR" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "Done: $DMG_PATH"
echo "SHA256:"
shasum -a 256 "$DMG_PATH" | awk '{print "  " $1}'