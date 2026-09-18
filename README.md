# Arc

A free, open-source music companion for macOS 14 and later. Arc puts music
controls beside your MacBook’s notch, or in a small floating bar on other screens.
It runs on your Mac with no account, subscription, or usage tracking.

Arc is an early version. It includes music controls, battery updates, a temporary
place to keep files, automatic screenshot copying, and menu bar icon hiding.

## Build And Run

You’ll need Xcode 15 or later with its command-line tools selected. Run these
commands from the project folder:

```sh
./scripts/build-app.sh
open dist/Arc.app
```

You don’t need Homebrew or extra Swift packages. Open `Package.swift` in Xcode
to edit the app. Use the build script above to run the full app: `swift run`
doesn’t include the helper Arc needs to connect to your music.

## Music Controls

Play music or a video, then move your pointer over the notch or floating bar.
Arc shows the title, artwork, and playback controls. You can pause, change
tracks, drag the progress bar to move through a track, or click the artwork
to open the app that’s playing. Paused tracks stay visible.

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
5. Click the arrow again to show those icons in their usual place. Click again
   to hide them when you’re done.

Your apps keep running while their icons are hidden. Arc doesn’t choose or move
icons for you. Icons from newly opened apps may appear in the hidden group.

The setup line only appears while you’re arranging icons. Arc remembers whether
Menu Pocket is on, and macOS manages the icon positions. Icons are shown again
when Arc starts or your display setup changes. Turning off Menu Pocket or
quitting Arc also shows them again.

**Space is still limited:** if too many icons are beside the notch, macOS may
leave some out even when Menu Pocket is open. You’ll need fewer menu bar icons
to fit them all. This feature still needs more testing with different screens.

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

Arc runs locally. It doesn’t request Accessibility, Screen Recording,
Notifications, Automation, or Input Monitoring permissions. Screenshot copying
reads saved files; Arc doesn’t take pictures of your screen. File access may
still need the usual macOS folder permission.

The app is not sandboxed, meaning macOS doesn’t restrict it to its own storage
folder. Music support uses a helper based on Apple’s private MediaRemote system,
which may stop working after a macOS update.

## For Developers

Arc uses SwiftUI and AppKit, with shared logic in `ArcCore` and tests in `Tests/`.
The build script creates an app for the type of Mac you’re using and bundles
the music helper. No third-party Swift packages are needed.

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
# Check the music connection without changing playback.
dist/Arc.app/Contents/MacOS/Arc --smoke-test
# Test Menu Pocket’s buttons and layout with temporary menu bar items.
dist/Arc.app/Contents/MacOS/Arc --menu-pocket-smoke-test
# Read the current battery status.
dist/Arc.app/Contents/MacOS/Arc --system-smoke-test
# Create sample images of the app for checking its appearance.
dist/Arc.app/Contents/MacOS/Arc --render-previews "$PWD/.build/previews"
```

The extra command options above are available in debug builds only. Tests cover
music details, playback progress, show/hide behavior, file handling, and layout.
The sample images include playing, paused, empty, error, screenshot, and Pocket
states.

### Known Limits

- Tested locally on macOS 26. Running on macOS 14 and Intel Macs still needs testing.
- More testing is needed with different music apps, full-screen apps, hidden
  menu bars, multiple screens, sleep/wake, Reduce Motion, and VoiceOver.
- Browser videos can appear as now playing. Arc doesn’t filter them out.
- Timers, AirPods features, general notifications, and extra islands aren’t included.
- Automatic updates and public releases aren’t set up yet.

## License

Arc uses the MIT license. MediaRemote Adapter keeps its BSD-3-Clause license
and credit. This version is intended for direct local use, not the Mac App Store.
Release signing and Apple’s security review for downloaded apps (notarization)
aren’t set up yet.
