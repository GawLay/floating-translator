# Help and troubleshooting

[← Back to the README](../README.md)

## Permissions and privacy

| Access | Why | When |
| --- | --- | --- |
| Screen Recording | macOS requires this to read pixels in another app. | Requested only when you click **Enable capture**. |
| Translation language download | Apple may need to install the chosen language models. | The first time you use a language pair. |

Opening the app and moving the scan area do not request permission. The app first performs a passive access check. If permission is missing, area capture waits and the results card shows **Enable capture**. Click that button to authorize the app in System Settings. macOS may require you to quit and reopen after granting access. Once granted, choosing a new area scans once. Moving or resizing an existing area scans automatically only when Live scan is enabled. Paste text remains available even without screen access.

macOS may describe Screen Recording as **“screen and audio.”** Floating Translator sets audio capture off and does not request microphone, camera, Accessibility, or contacts access. It takes one display frame, crops it to the chosen area in memory, and discards the image after OCR. It does not save messages or screenshots. Translation runs through Apple's [on-device Translation framework](https://developer.apple.com/documentation/translation/translationsession).

## Permission troubleshooting

### Why did the permission dialog keep appearing?

During early development, local builds used **ad hoc signing**. Each rebuild changed the app's code identity, so macOS could stop associating it with the permission you had already granted. The Settings toggle could still show the old build as enabled. Repeated capture attempts then brought the dialog back. Apple explains this behavior in its [code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).

The current build reuses a persistent certificate. The app also checks access before capturing, requests permission only through **Enable capture**, and pauses automatic capture when access is missing or declined. Switching from an old build to the new signing identity may require one fresh grant; ordinary updates using the same identity should retain it.

### Screen Recording is enabled, but capture is blocked

1. Quit all running copies using the app's **Quit** button. Closing the window can leave the menu bar app running.
2. Open the copy in **Applications**, then click **Enable capture** and check its Screen Recording setting. If the app is missing from the list, use **+** to add the installed copy. See [Apple's screen access guide](https://support.apple.com/guide/mac-help/control-access-to-screen-and-system-audio-recording-mchld6aa7d23/mac).
3. Quit and reopen the installed copy after changing access. For local builds, keep the [local signing directory](../CONTRIBUTING.md#signing-and-releases) and use the same signing certificate for updates.

<details>
<summary>Advanced: clear an old grant or check access without capturing</summary>

If an old, mismatched grant remains stuck, quit the app and reset **only Floating Translator's** Screen Recording grant:

```sh
tccutil reset ScreenCapture dev.phyo.floatingtranslator
```

This removes its current grant. Reopen the installed app, click **Enable capture**, and approve it again. This is a recovery step, not part of routine installation or updates.

For a passive diagnostic without capturing or showing a window, quit the app first, then run:

```sh
open -a 'Floating Translator' --args --diagnose-screen-access
```

The result is written to `~/Library/Application Support/Floating Translator/capture-status.json`; it contains only the app path, version, and whether macOS grants screen access.

</details>

## Notes

- Keep the scan area entirely on one display. If OCR misses small text, zoom the source app or use **Paste text**.
- Available language pairs depend on macOS support and installed models. The app checks the chosen pair before translating and explains when the current macOS version does not support it. Malay translation in particular may require a newer macOS release.
- The menu bar shortcut appears while the app runs. If macOS hides it because the menu bar is crowded, use the Dock icon to reopen the window.
- Live scan is optional, off at launch, and runs only for a visible scan area. It pauses while you interact with the results card; hiding the app stops it.

## Updating

Download or pull the latest source and run `./build.sh` again. Quit the running app using **Quit**, replace the copy in **Applications** with the newly built app, and reopen it there. Keep the same local signing identity so macOS can recognize the update.

## Selected-text Services

Select text in a supported app and choose **Services → Translate with Floating Translator**. You can enable the service or assign a shortcut in **System Settings → Keyboard → Keyboard Shortcuts → Services**. If the source app does not support Services, copy the text and press **⌃⌥⌘T** instead. See [Apple’s Services guide](https://support.apple.com/guide/mac-help/mchlp1012/mac).

Global shortcuts work while Floating Translator runs. If another app already uses one, use the menu bar or the buttons instead. **Return** refreshes with the results card focused; **⌘Return** translates an edit to the original; **Esc** cancels area selection.

## Reading and capture tips

Drag the scan frame’s solid grip to move it, and its edges or handles to resize it. The clear center lets you click the source app. Resize the results card independently from its bottom-right grip, and drag the divider to adjust the Original and Translation panes.

Use **Aa** for text size, collapse **Original** for more reading space, or edit it to correct OCR mistakes. Paragraph grouping is heuristic, especially with headings, lists, and multiple columns.

Text and translations stay in memory; no conversation history is saved. Saved preferences include font size, pane proportions, pin state, and window/scan rectangle coordinates.
