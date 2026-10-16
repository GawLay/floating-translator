#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
# Clang's compiled modules embed their cache path, so discard the generated
# cache when the repository has been moved or copied.
rm -rf .build/clang-cache
mkdir -p .build/clang-cache build/'Floating Translator.app'/Contents/MacOS \
  build/'Floating Translator.app'/Contents/Resources

# Prefer the compatible macOS 15.4 SDK when available; otherwise use the
# selected toolchain's SDK. Keep the deployment target independent of the host OS.
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [[ ! -d "$sdk_path" ]]; then
  sdk_path=$(xcrun --show-sdk-path)
fi
swiftc -parse-as-library -swift-version 5 -O \
  -target "$(uname -m)-apple-macosx15.0" \
  -sdk "$sdk_path" \
  -module-cache-path .build/clang-cache \
  -framework AppKit -framework SwiftUI -framework Vision \
  -framework ScreenCaptureKit -framework Translation -framework Carbon \
  Sources/*.swift \
  -o 'build/Floating Translator.app/Contents/MacOS/FloatingTranslator'
cp Info.plist 'build/Floating Translator.app/Contents/Info.plist'
cp Assets/AppIcon.icns 'build/Floating Translator.app/Contents/Resources/AppIcon.icns'
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$CODESIGN_IDENTITY" 'build/Floating Translator.app'
else
  zsh scripts/sign-local.sh 'build/Floating Translator.app'
fi
echo "Built: $PWD/build/Floating Translator.app"
