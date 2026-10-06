#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
# Clang's compiled modules embed their cache path, so discard the generated
# cache when the repository has been moved or copied.
rm -rf .build/clang-cache
mkdir -p .build/clang-cache build/'Floating Translator.app'/Contents/MacOS \
  build/'Floating Translator.app'/Contents/Resources

# The installed command line compiler is currently newer than the macOS 26 SDK.
# The macOS 15.4 SDK supports all APIs this app uses and matches this compiler.
sdk_path=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
if [[ ! -d "$sdk_path" ]]; then
  sdk_path=$(xcrun --show-sdk-path)
fi
swiftc -parse-as-library -swift-version 5 -O \
  -sdk "$sdk_path" \
  -module-cache-path .build/clang-cache \
  -framework AppKit -framework SwiftUI -framework Vision \
  -framework ScreenCaptureKit -framework Translation -framework Carbon \
  Sources/FloatingTranslator.swift \
  -o 'build/Floating Translator.app/Contents/MacOS/FloatingTranslator'
cp Info.plist 'build/Floating Translator.app/Contents/Info.plist'
cp Assets/AppIcon.icns 'build/Floating Translator.app/Contents/Resources/AppIcon.icns'
codesign --force --sign - 'build/Floating Translator.app'
echo "Built: $PWD/build/Floating Translator.app"
