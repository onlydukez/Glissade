#!/bin/zsh
# Builds build/Glissade.app. Usage: ./build.sh
set -e
cd "${0:a:h}"
source ./toolchain.sh

app=build/Glissade.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
"${SWIFTC[@]}" -O -module-name Glissade Sources/Core/*.swift Sources/App/*.swift -o $app/Contents/MacOS/Glissade
cp Resources/Info.plist $app/Contents/

if [[ ! -f build/AppIcon.icns || Tools/icon.swift -nt build/AppIcon.icns ]]; then
  mkdir -p build/AppIcon.iconset
  "${SWIFTC[@]}" Tools/icon.swift -o build/icon
  ./build/icon build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns $app/Contents/Resources/

# Signed for this Mac only. Pass SIGN_ID to use a real identity, which lets the
# Accessibility permission survive rebuilds.
codesign --force --sign "${SIGN_ID:--}" $app
echo "Built $app"
