#!/bin/bash
#
# 为每个目标架构产出独立的 .app bundle（不分发 universal 二进制）。
# 默认同时构建 arm64 和 x86_64，得到两份 .app。
#
# 用法：
#   ./scripts/build-release.sh                       # 默认 arm64 + x86_64，各一份 .app
#   ./scripts/build-release.sh --arch arm64          # 仅 Apple Silicon
#   ./scripts/build-release.sh --arch x86_64         # 仅 Intel
#   ./scripts/build-release.sh --arch arm64 --arch x86_64
#   ./scripts/build-release.sh --dmg                # 顺便为每个 .app 打成 DMG
#
# 输出：
#   build/CCStatus-arm64.app
#   build/CCStatus-x86_64.app
#   （加 --dmg 时附带 .dmg，DMG 文件名带 <version>-<arch>）
#
# .app bundle 内部名字始终是 CCStatus（干净名），版本和架构信息放在
# Info.plist 和 DMG 文件名里——用户打开 DMG 看到的就是 CCStatus.app。
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="CCStatus"

usage() {
    sed -n '2,18p' "$0"
    exit "${1:-0}"
}

# 从 git 推断版本号
VERSION="$(git -C "$PROJECT_DIR" describe --tags --always --dirty 2>/dev/null \
    | sed 's/^v//' | sed 's/-g[0-9a-f]\{7,\}//' | sed 's/-dirty//')"
VERSION="${VERSION:-0.0.0}"

USER_ARCHS=()   # 用户显式传入的架构（去重）
BUILD_DMG=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || { echo "error: --arch requires a value" >&2; usage 2; }
            USER_ARCHS+=("$2"); shift 2 ;;
        --arch=*) USER_ARCHS+=("${1#*=}"); shift ;;
        --dmg) BUILD_DMG=1; shift ;;
        -h|--help) usage ;;
        *) echo "unknown arg: $1" >&2; usage 2 ;;
    esac
done

# 去重并保持顺序（兼容 bash 3.2，无关联数组）
FINAL_ARCHS=()
if [[ "${#USER_ARCHS[@]}" -gt 0 ]]; then
    for a in "${USER_ARCHS[@]}"; do
        if [[ ! " ${FINAL_ARCHS[*]} " =~ " $a " ]]; then
            FINAL_ARCHS+=("$a")
        fi
    done
fi

# 用户没传就用默认
if [[ ${#FINAL_ARCHS[@]} -eq 0 ]]; then
    FINAL_ARCHS=("arm64" "x86_64")
fi

cd "$PROJECT_DIR"

# 输出到 build/ 子目录，避免污染项目根
BUILD_OUTPUT_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_OUTPUT_DIR"

echo "==> Building $APP_NAME $VERSION for: ${FINAL_ARCHS[*]}"
swift package clean

BUILT_APPS=()
for ARCH in "${FINAL_ARCHS[@]}"; do
    echo ""
    echo "==> [$ARCH] swift build -c release --arch $ARCH"
    swift build -c release --arch "$ARCH"

    BIN="$PROJECT_DIR/.build/$ARCH-apple-macosx/release/$APP_NAME"
    if [[ ! -f "$BIN" ]]; then
        echo "error: built binary not found at $BIN" >&2
        exit 1
    fi

    # .app 名字始终是干净的 CCStatus.app；架构仅出现在输出目录里
    APP_BUNDLE="$BUILD_OUTPUT_DIR/$APP_NAME-$ARCH/$APP_NAME.app"
    echo "==> [$ARCH] Assembling $APP_BUNDLE"
    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    cp "$PROJECT_DIR/Sources/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/"

    if [[ -f "$PROJECT_DIR/Sources/$APP_NAME/Resources/AppIcon.icns" ]]; then
        cp "$PROJECT_DIR/Sources/$APP_NAME/Resources/AppIcon.icns" \
           "$APP_BUNDLE/Contents/Resources/"
    fi

    # Copy localization bundles (.lproj directories)
    for lproj in "$PROJECT_DIR/Sources/$APP_NAME/Resources"/*.lproj; do
        [ -d "$lproj" ] && cp -R "$lproj" "$APP_BUNDLE/Contents/Resources/"
    done

    # 注入版本号
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" \
        "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" \
        "$APP_BUNDLE/Contents/Info.plist"

    # ad-hoc 签名
    echo "==> [$ARCH] Codesign (ad-hoc)"
    codesign --force --deep --sign - "$APP_BUNDLE"

    # 校验
    echo "==> [$ARCH] Verify arch:"
    lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    BUILT_APPS+=("$APP_BUNDLE")
done

echo ""
echo "==> Built apps:"
for app in "${BUILT_APPS[@]}"; do
    echo "    - $app"
done

# 可选：把每个 .app 打成 DMG
if [[ "$BUILD_DMG" -eq 1 ]]; then
    echo ""
    echo "==> Building DMGs"
    for app in "${BUILT_APPS[@]}"; do
        "$SCRIPT_DIR/build-dmg.sh" "$app"
    done
fi

echo ""
echo "Done."
for app in "${BUILT_APPS[@]}"; do
    echo "  open \"$app\""
done