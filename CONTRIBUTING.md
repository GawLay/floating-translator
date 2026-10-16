# Contributing

Thanks for helping improve Floating Translator.

## Build and check

1. Use macOS 15 or later with Apple Command Line Tools.
2. Run `./build.sh`. This compiles the Swift source, packages the icon, and signs the app locally.
3. Keep private screenshots, message text, permission settings, and local build output out of commits. Public documentation screenshots belong in `Assets/`.

Please keep new dependencies optional. Live scan starts off. Opening, moving, or resizing an unapproved area must never request permission. Request Screen Recording only through the explicit **Enable capture** button. Keep the persistent local signing identity across builds so updates retain their screen-access grant. Translation uses Apple's on-device framework.

The source icon is `Assets/AppIcon.png`; `Assets/AppIcon.icns` is its macOS app bundle version. `scripts/make-icon.swift` contains the drawing code for the source image.

## Paragraph formatting checks

After building, run the OCR layout fixtures:

```sh
swiftc -parse-as-library -module-cache-path .build/test-cache \
  Sources/RecognizedParagraphs.swift Tests/ParagraphFormattingTests.swift \
  -o .build/paragraph-tests
.build/paragraph-tests
```

Use synthetic text for UI and service checks. Do not capture private screen content as a test fixture.

## Translation refresh checks

With Vietnamese and English models already installed, run the native session regression:

```sh
swiftc -parse-as-library -swift-version 5 -module-cache-path .build/refresh-test-cache \
  Sources/FloatingTranslator.swift Sources/ResultsCard.swift Tests/TranslationRefreshTests.swift \
  -o .build/translation-refresh-tests
.build/translation-refresh-tests
```

This briefly opens a test window and checks repeated Refresh, replacement text, interrupted work, language changes, and reopening. It uses synthetic text, skips with exit code 77 if models are missing, and never requests screen access or downloads models.

## Signing and releases

The app uses Apple's AppKit, SwiftUI, Vision, ScreenCaptureKit, Translation, and Carbon frameworks.

Local builds reuse a persistent signing certificate. The first build creates a dedicated private keychain in `~/Library/Application Support/Floating Translator/Signing` and a user-level trust entry scoped to that certificate's code-signing use. Later builds reuse it so macOS can recognize updates as the same app. Keep this directory private, retain it across builds, and back it up. The private key is never placed in this repository.

If you have an Apple Development or Developer ID signing identity, set `CODESIGN_IDENTITY` instead:

```sh
CODESIGN_IDENTITY='your signing identity' ./build.sh
```

The local certificate is for development on your own Mac. Public binary releases should use Developer ID signing and notarization. Changing the signing certificate can require a fresh permission grant.
