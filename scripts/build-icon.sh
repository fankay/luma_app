#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Assets/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/AppIcon-source.png --out "Assets/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/AppIcon-source.png --out "Assets/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
