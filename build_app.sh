#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DiskInfo"
APP_BUNDLE="${APP_NAME}.app"

echo "🔨 正在編譯 ${APP_NAME} (Release 模式)..."
mkdir -p .build/release

VFS_ARGS=()
if [[ -f "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap" && -f "/Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap" ]]; then
    mkdir -p .build/vfs
    : > .build/vfs/empty.modulemap
    cat > .build/vfs/swift_fix_vfs.yaml <<VFS_EOF
{
  'version': 0,
  'use-external-names': false,
  'roots': [
    {
      'name': '/Library/Developer/CommandLineTools/usr/include/swift',
      'type': 'directory',
      'contents': [
        {
          'name': 'module.modulemap',
          'type': 'file',
          'external-contents': '$(pwd)/.build/vfs/empty.modulemap'
        }
      ]
    }
  ]
}
VFS_EOF
    VFS_ARGS=(-vfsoverlay "$(pwd)/.build/vfs/swift_fix_vfs.yaml" -Xcc -ivfsoverlay -Xcc "$(pwd)/.build/vfs/swift_fix_vfs.yaml")
fi

SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"
BIN_PATH="$(pwd)/.build/release/${APP_NAME}"

swiftc -O \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$(pwd)/.build/module-cache" \
    "${VFS_ARGS[@]}" \
    Sources/DiskInfo/*.swift \
    -o "${BIN_PATH}"

echo "📦 正在打包 macOS 應用程式 ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.diskinfo</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>DiskInfo 磁碟空間分析</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "✅ 建置完成：$(pwd)/${APP_BUNDLE}"
if [[ "${1:-}" == "--run" ]]; then
    echo "🚀 正在啟動 ${APP_BUNDLE}..."
    open "${APP_BUNDLE}"
fi
