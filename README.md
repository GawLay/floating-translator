<p align="center">
  <img src="Assets/AppIcon.png" alt="Floating Translator icon" width="96">
</p>

<h1 align="center">Floating Translator</h1>

<p align="center">
  A tiny floating translator for text in other Mac apps.<br>
  Select text or draw a scan area, and keep reading without switching apps.
</p>

<p align="center">
  <strong>macOS 15+</strong> · <strong>On-device translation</strong> · <strong>No API key</strong> · <strong>MIT</strong>
</p>

## Download

**Source code only for now — there is no prebuilt app download.** Click **Code → Download ZIP** on GitHub and extract it, or clone this repository. Build the app on your Mac using the steps below. No paid Apple developer account is needed.

## Install

1. Install Apple’s Command Line Tools if needed:

   ```sh
   xcode-select --install
   ```

2. Open Terminal in the extracted repository folder and run:

   ```sh
   ./build.sh
   ```

3. Drag **`build/Floating Translator.app`** into **Applications**, then open that copy. The build script handles local signing automatically.
4. For screen capture, choose **New area**, draw a rectangle, then click **Enable capture** if prompted in the app. Enable Floating Translator in **System Settings → Privacy & Security → Screen Recording** (sometimes called **Screen & System Audio Recording**). Quit and reopen if macOS asks.

Selected or pasted text works **without screen access**. Apple may download translation languages on first use. For updates, rebuild, quit the app, and replace the Applications copy. [Permission or update trouble?](docs/troubleshooting.md)

## Preview

<p align="center">
  <img src="Assets/preview-0.4.png" alt="Floating Translator: a resizable scan frame beside an independent dark translation card" width="960">
</p>

*Current native UI with sample text: a movable scan frame and a separate results card.*

## Use it

- **Screen text:** choose **New area** and draw over the words. Drag the frame’s grip to move it; drag an edge or handle to resize. **Refresh** reads it again. **Live scan** is optional and starts off.
- **Selected text:** choose **Services → Translate with Floating Translator** in a supported app. Otherwise, copy text and use **Paste text** or **⌃⌥⌘T**.
- **Read comfortably:** resize the results card, drag the pane divider, collapse or edit **Original**, adjust **Aa**, and pin the card above other apps.

Vietnamese → English by default, plus Thai, Malay, and other Apple-supported language pairs. Availability depends on macOS and downloaded models. Open the card from the **menu bar lens icon**, Dock, or shortcut.

## Shortcuts

Global shortcuts work while the app is running.

| Shortcut | Action |
| --- | --- |
| ⌥⌘T | Show / hide the translator |
| ⌥⌘N | Draw a new scan area |
| ⌥⌘R | Refresh the current area or text |
| ⌥⌘A | Toggle Live scan |
| ⌃⌥⌘T | Translate copied text |
| Return | Refresh while the card is focused, except when editing |
| ⌘Return | Translate an edit to the original |
| Esc | Cancel area selection |

Assign a selected-text Service shortcut in **System Settings → Keyboard → Keyboard Shortcuts → Services**.

## Why

This started as a small tool for my own everyday use and grew into a hobby project. I kept finding text in apps and images that was awkward to translate. I wanted something small and cozy that lets me read it and get back to what I was doing. Sharing it in case it helps you too :)

## Privacy & open source

Translation runs on-device through Apple’s frameworks. Screen access is requested only through **Enable capture**; audio capture is off. Screenshots and translations are not saved.

[Help & permission troubleshooting](docs/troubleshooting.md) · [Contributing & build notes](CONTRIBUTING.md) · [MIT License](LICENSE)
