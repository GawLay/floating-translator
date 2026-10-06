# Contributing

Thanks for helping improve Floating Translator.

## Build and check

1. Use macOS 15 or later with Apple Command Line Tools.
2. Run `./build.sh`. This compiles the Swift source, packages the icon, and signs the app locally.
3. Keep screenshots, message text, permission settings, and local build output out of commits.

Please keep new dependencies optional. For capture changes, preserve the user-initiated default: Auto Scan starts off, and the app should request only Screen Recording when it needs to read another app's pixels. Translation uses Apple's on-device framework.

The source icon is `Assets/AppIcon.png`; `Assets/AppIcon.icns` is its macOS app bundle version. `scripts/make-icon.swift` contains the drawing code for the source image.
