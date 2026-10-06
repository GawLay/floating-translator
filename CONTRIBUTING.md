# Contributing

Thanks for helping improve Floating Translator.

## Build and check

1. Use macOS 15 or later with Apple Command Line Tools.
2. Run `./build.sh`. This compiles the Swift source, packages the icon, and signs the app locally.
3. Keep private screenshots, message text, permission settings, and local build output out of commits. Public documentation screenshots belong in `Assets/`.

Please keep new dependencies optional. Auto Scan starts on, but opening or moving an unapproved lens must never request permission. Request Screen Recording only through the explicit **Enable capture** button. Keep the persistent local signing identity across builds so updates retain their screen-access grant. Translation uses Apple's on-device framework.

The source icon is `Assets/AppIcon.png`; `Assets/AppIcon.icns` is its macOS app bundle version. `scripts/make-icon.swift` contains the drawing code for the source image.
