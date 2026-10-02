#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/prepare-resources.sh
./scripts/swift.sh build -c release
bin=$(./scripts/swift.sh build -c release --show-bin-path | tail -1)
app="dist/Offline EDA Studio.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist
# Remove only the stale bundle placed by an older development packaging layout.
rm -rf "$app/OfflineEDAStudio_EDAStudio.bundle"
cp "$bin/EDAStudio" "$app/Contents/MacOS/EDAStudio"
cp "$bin/eda" dist/eda
for bundle in "$bin"/*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "$app/Contents/Resources/"

done
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.offline-eda.studio</string>
<key>CFBundleName</key><string>Offline EDA Studio</string>
<key>CFBundleDisplayName</key><string>Offline EDA Studio</string>
<key>CFBundleExecutable</key><string>EDAStudio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Offline-EDA-Studio-macOS-$(uname -m).zip"
printf '%s\n' "$app"
