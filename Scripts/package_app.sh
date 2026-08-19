#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
package_dir="$repo_dir/.build/package"
app_dir="$package_dir/PRPulse.app"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS"
cp "$bin_dir/PRPulse" "$app_dir/Contents/MacOS/PRPulse"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PRPulse</string>
    <key>CFBundleIdentifier</key>
    <string>com.prpulse.PRPulse</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PR Pulse</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$app_dir"
rm -rf "$repo_dir/PRPulse.app"
cp -R "$app_dir" "$repo_dir/PRPulse.app"

echo "Built $repo_dir/PRPulse.app"
