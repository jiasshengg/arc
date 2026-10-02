# Arc

> Music controls, useful files, and a little more room in your menu bar.

Arc is a free, open-source utility for macOS 14 and later. It places a small
island beside your MacBook’s notch, at the top of a mirrored display, or below
the menu bar on other screens. Everything runs locally, with no account,
subscription, or usage tracking.

## Features

- **Music controls:** See what’s playing, pause, skip, seek, or open the playing app.
- **Pocket:** Keep files and folders close by without moving the originals.
- **Menu Pocket:** Hide less-used menu bar icons and open them from a separate row.
- **Screenshot copying:** Copy newly saved screenshots to the clipboard automatically.
- **Battery updates:** See brief charging and low-battery messages in the island.

Arc is still an early version. See [Known Limits](#known-limits) before relying on
it across different Macs and media apps.

## Install

1. Download the DMG from [Releases](https://github.com/jiasshengg/arc/releases).
2. Open the DMG and copy Arc to Applications.
3. Launch Arc from Applications. Its icon appears in the menu bar.

The DMG does not require Xcode, Homebrew, or terminal commands.

## Music Controls

Play music or a video, then move your pointer over the island to open its
controls. You can pause, change tracks, drag the progress bar to move through
a track, or click the artwork to open the app that’s playing. Paused tracks
stay visible.

Click Arc’s main icon in the menu bar for these options:

- **Show Island** — show or hide the music bar.
- **Launch At Login** — start Arc when you log in. This is off by default.
- **Try Connecting Again** — reconnect if Arc can’t read what’s playing.
- **Open Pocket…** — open your temporary file list.
- **Quit Arc** — close Arc.

Keep Arc in a permanent folder before turning on **Launch At Login**. macOS
may ask you to allow it in System Settings.

## Pocket

Drag files or folders from Finder onto the island to keep them nearby.
The first five appear in the island. If you add more, click **More** or choose
**Open Pocket…** from Arc’s menu to see the full list.

Drag a file from Pocket into another app, such as Mail or Messages. Click **×**
to remove one item from Pocket, or **Clear** to empty the list. Your original
files stay where they are. Pocket’s list clears when Arc quits.

Pocket doesn’t upload or duplicate your files. If you move or delete an original
file, its entry shows a warning. Adding the same file twice won’t create a
second entry. You can add existing files and folders; pasting text or dragging
images straight from a browser isn’t supported yet. Dragging into different
apps still needs more testing.

## Menu Pocket

Turn on **Menu Pocket** in Arc’s menu. An arrow appears in the menu bar.
To choose which icons to hide:

1. Choose **Arrange Menu Pocket…**. A temporary vertical line appears.
2. Hold **Command** and drag icons you want to hide, such as ChatGPT or Teams,
   to the **left of the line**. Keep the line to the **left of Arc’s arrow**.
3. Keep Arc’s main icon, battery, Wi-Fi, Search, and Control Centre to the
   **right of the line**.
4. Click the arrow. The line and the icons on its left disappear.
5. Click the arrow again to open a scrollable row below the menu bar. Select an
   item there to temporarily show just that icon and open its original control.
   Click the arrow again to put it back and reopen the row. Click × to close
   the row.

The arrow points down when the row can be opened and up when it can be closed
or the inline icons can be hidden.

To move an icon out of Menu Pocket, choose **Arrange Menu Pocket…**, then hold
**Command** and drag its actual menu-bar icon to the **right of the line**.
Use the actual menu bar to rearrange icons; dragging them in the popup row isn’t
supported. Click the arrow when you’re finished arranging.

Your apps keep running while their icons are hidden. You choose which icons
belong in the group. Arc temporarily moves the selected icon to open its menu
and returns it when you reopen the row. Icons from newly opened apps may appear
in the hidden group.

The setup line only appears while you’re arranging icons. Arc remembers whether
Menu Pocket is on, and macOS manages the icon positions. When Arc starts with
Menu Pocket already on, your chosen icons start hidden. The row needs
Accessibility permission to find and open other apps’ menu bar controls. It
uses each app’s icon and name to represent the control; these may differ from
the tiny icon in the menu bar. Turning off Menu Pocket or quitting Arc shows
the icons again.

Some apps may not expose their controls to Accessibility, so this first version
still needs testing with different apps and screens.

## Screenshots

Take a screenshot with **Shift-Command-3** or **Shift-Command-4**. Arc copies
newly saved screenshots to the clipboard and briefly shows **Screenshot Copied**
in the island. You can paste the image into another app. The saved file stays
where macOS put it.

Arc watches the screenshot folder set in macOS. Restart Arc if you change that
folder. macOS may ask for permission to read it. Ordinary images added to the
folder are ignored.

Holding **Control** with the screenshot shortcut already copies the image
directly to the clipboard. It doesn’t save a file, so Arc won’t show a message.

## Battery Updates

Arc briefly shows when you connect or disconnect power, fully charge the
battery, or reach 20% and 10%. Each update lasts 1.5 seconds before your music
returns. You can also check the battery level in Arc’s menu.

Arc leaves volume and screen brightness messages to macOS.

## Privacy And Permissions

Arc runs locally. Menu Pocket asks for Accessibility permission to find,
temporarily move, and open hidden menu bar controls from its separate row. Arc
doesn’t request Screen Recording, Notifications, Automation, or Input Monitoring
permissions.
Screenshot copying reads saved files; Arc doesn’t take pictures of your screen.
File access may still need the usual macOS folder permission.

The app is not sandboxed, meaning macOS doesn’t restrict it to its own storage
folder. Music support uses a helper based on Apple’s private MediaRemote system,
which may stop working after a macOS update.

## For Developers

Arc uses SwiftUI and AppKit, with shared logic in `ArcCore` and tests in `Tests/`.
The build script creates an app for the type of Mac you’re using and bundles
the music helper. No third-party Swift packages are needed.

### Build From Source

You’ll need Xcode 15 or later with its command-line tools selected. From the
project folder, run:

```sh
./scripts/build-app.sh
open dist/Arc.app
```

The default build is optimized for everyday use. Use `./scripts/build-app.sh debug`
for the development checks below. You don’t need Homebrew or extra Swift
packages. Open `Package.swift` in Xcode to edit the app. Use the build script
to run the full app: `swift run` doesn’t include the helper Arc needs to connect
to your music.

The island uses a transparent window that stays in place while the visible
content expands. Rounded corners let clicks pass through. Arc prefers the
built-in notched display and otherwise uses the main display. It supports one
island at a time.

Music updates come from the bundled BSD-licensed
[MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter), whose source
is kept in `Vendor/`. Arc runs it in a separate process through Apple’s system
Perl. The helper sends music details and playback commands. If it fails, use
**Try Connecting Again**. Arc restarts the connection after your Mac wakes.

Battery updates use IOKit. Screenshot copying watches the saved screenshot
folder and checks the file information macOS adds to screenshots. These checks
pause during sleep. Battery monitoring also pauses when the island is hidden.

### Run Checks

```sh
swift test
./scripts/build-app.sh debug
# Measure UI CPU usage with synthetic media (keep the pointer away from the island).
dist/Arc.app/Contents/MacOS/Arc --performance-check
# Check the music connection without changing playback.
dist/Arc.app/Contents/MacOS/Arc --smoke-test
# Test Menu Pocket’s buttons and layout with temporary menu bar items.
dist/Arc.app/Contents/MacOS/Arc --menu-pocket-smoke-test
# Inspect Menu Pocket’s Accessibility access and icon geometry without moving icons.
dist/Arc.app/Contents/MacOS/Arc --menu-pocket-diagnose
# Read the current battery status.
dist/Arc.app/Contents/MacOS/Arc --system-smoke-test
# Create sample images of the app for checking its appearance.
dist/Arc.app/Contents/MacOS/Arc --render-previews "$PWD/.build/previews"
```

The extra command options above are available in debug builds only. Tests cover
music details, playback progress, show/hide behavior, file handling, and layout.
Menu Pocket checks also cover native event routing, cursor restoration decisions,
and grouping after the divider moves. The native smoke check exercises Arc’s
buttons and layout; it does not verify opening real third-party app menus.
The sample images include playing, paused, empty, error, screenshot, and Pocket
states.

### Known Limits

- Tested locally on macOS 26. Running on macOS 14 and Intel Macs still needs testing.
- More testing is needed with different music apps, full-screen apps, hidden
  menu bars, multiple screens, sleep/wake, Reduce Motion, and VoiceOver.
- Menu Pocket’s menu opening, icon restoration, and pointer behavior still need
  hands-on testing across third-party apps. Before a release, check opening and
  closing menus repeatedly and confirm all grouped icons remain in the row.
- Browser videos can appear as now playing. Arc doesn’t filter them out.
- Timers, AirPods features, general notifications, and extra islands aren’t included.
- Automatic updates and release packaging aren’t automated yet.

## License

Arc uses the MIT license. MediaRemote Adapter keeps its BSD-3-Clause license
and credit. This version is intended for direct local use, not the Mac App Store.
The build script uses a local ad-hoc signature. Developer ID signing and
notarization for downloaded apps aren’t set up yet.
