#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=10.0.6
file="kicad-unified-universal-${version}.dmg"
expected=ef4dcd4278c46d3efcd28c8db273d5957d68efda028f6bf79b4811fc5302dc68
mkdir -p engine
if [[ ! -f "engine/$file" ]]; then
  curl -fL --retry 2 "https://github.com/KiCad/kicad-source-mirror/releases/download/$version/$file" -o "engine/$file.partial"
  actual=$(shasum -a 256 "engine/$file.partial" | cut -d' ' -f1)
  [[ "$actual" == "$expected" ]] || { printf '%s\n' 'SHA-256 mismatch'; exit 1; }
  mv "engine/$file.partial" "engine/$file"
fi
actual=$(shasum -a 256 "engine/$file" | cut -d' ' -f1)
[[ "$actual" == "$expected" ]] || { printf '%s\n' 'SHA-256 mismatch'; exit 1; }
printf '%s\n' "Verified engine/$file" '打开 DMG，将 KiCad 文件夹复制到 /Applications；完整保留内置库及模型。'
