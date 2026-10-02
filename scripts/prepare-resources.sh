#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-features.py
mkdir -p Sources/EDAStudio/Resources/docs Sources/EDAStudio/Resources/led-demo
cp Resources/features.json Sources/EDAStudio/Resources/features.json
# Generated outputs and user snapshots must never enter app resources.
for file in examples/led-demo/*; do
  if [[ "$(basename "$file")" != outputs ]]; then
    cp -R "$file" Sources/EDAStudio/Resources/led-demo/
  fi
done
cp -R docs/. Sources/EDAStudio/Resources/docs/
