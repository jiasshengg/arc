# Arc

A free, open-source Dynamic Island-style music companion for macOS 14+.
Native SwiftUI and AppKit. No accounts, backend, telemetry, or subscriptions.

**Local prototype:** compact now playing, hover-to-expand artwork and transport
controls, live progress, paused and idle states, system level/battery indicators,
and menu-bar settings.

## Build and run

Requires Xcode 15+ with its command-line tools selected. No Homebrew packages or
third-party Swift dependencies are needed.

```sh
./scripts/build-app.sh
open dist/Arc.app
```

Hover over the MacBook notch (or the floating pill on a display without a notch). Start playback in a media app to
see its title and artwork; hover to reveal previous, play/pause, and next.
Arc's capsule icon in the menu bar provides show/hide, launch at login, retry
when the media connection fails, and Quit. Launch at login is off by default;
it uses the system's actual registration status. Keep the app in a stable
location before enabling it.

Open `Package.swift` in Xcode to edit and run tests. Use the script to run the
complete app: `swift run` alone does not bundle the media helper and will show
“Media integration unavailable.” The build targets the current Mac's architecture.

## Verify

```sh
swift test
# Development build only: read real media for two seconds without changing playback.
dist/Arc.app/Contents/MacOS/Arc --smoke-test
# Render synthetic UI fixtures without screen capture permissions.
dist/Arc.app/Contents/MacOS/Arc --render-previews "$PWD/.build/previews"
```

Tests cover metadata replacement, malformed values, paused/progress behavior,
hover cancellation, hidden state, and display geometry. Preview fixtures cover
idle, compact, expanded, paused, long titles, missing artwork, and unavailable.

Still needs hands-on validation across Apple Music, Spotify, browsers, fullscreen
Spaces, menu-bar auto-hide, sleep/wake, monitor changes, Reduce Motion, and VoiceOver.
This prototype has been compiled and its media bridge exercised on macOS 26;
macOS 14 and Intel runtime compatibility have not yet been tested.

## How it works

A non-activating AppKit panel hosts SwiftUI on the built-in notched display when
available, otherwise the primary menu-bar display. It measures the camera housing
from NSScreen’s safe-area and auxiliary-area geometry. Compact artwork and bars
sit on either side of the notch; expanded controls stay below it. On notchless
displays, the pill floats below the menu bar. A stationary transparent window
hosts a single SwiftUI spring animation, keeping expansion anchored at the top.
Pointer hit testing follows the visible shape inside that canvas. Pointer movement controls expansion after 100 ms and
collapse after 100 ms. Rounded transparent corners allow clicks through.
Paused music stays visible. Progress refreshes only while playing and expanded;
the equalizer runs at 30 updates per second while playing for smoother motion
and stops when hidden, paused, or Reduce Motion is enabled.

MediaRemote is private and direct in-process access is restricted on recent
macOS versions. Arc bundles the BSD-licensed
[MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter), pinned as
source under `Vendor/`. It runs through Apple's system Perl, streams complete
metadata updates, and sends commands to the active system media session.
The bridge is isolated in a child process and missing/broken helpers produce an
unavailable state with a manual retry. Arc restarts the listener after wake.
No Accessibility, Screen Recording, Notifications, or Automation permission is
requested by Arc. The app is not sandboxed.

Volume/mute changes show a brief white level indicator. Brightness feedback is
triggered only by brightness-key presses, so ambient-light adjustments, wake
restoration, and Control Center slider changes stay silent. Enable it from Arc's
**Enable brightness key indicator…** menu item, grant **Input Monitoring** in
System Settings, then relaunch Arc if macOS requests it. Arc uses a listen-only
system-event tap, filters for brightness keys, and neither stores keyboard input
nor intercepts the original event. Without permission, brightness feedback is off;
music, volume, and battery still work. Local ad-hoc rebuilds may require renewed
permission. The brightness level itself uses a dynamically loaded DisplayServices
reader, only on key presses; there is no background brightness polling. Unsupported
displays are skipped, with built-in displays preferred (no generic DDC/CI support).

Power connection, disconnection, full charge, and low battery (20% and 10%) show
battery feedback. Each indicator lasts 1.5 seconds after the latest change, then
returns to music or idle. Battery status also appears in the menu. Monitoring
pauses when hidden or asleep. Volume and battery use system notifications.
macOS's own HUD remains visible.

Read-only local check: `dist/Arc.app/Contents/MacOS/Arc --system-smoke-test`.
Hardware interaction testing (keys, output switching, plugging power) remains manual.

The prototype has no timer, AirPods, general notifications, or multi-display
islands. It also displays browser media when macOS reports it; there is no
reliable universal music-only filter. Notifications drive media updates; there
is no periodic polling fallback yet. Private API compatibility may change.

## License

Arc is MIT licensed. The vendored MediaRemote Adapter retains its BSD-3-Clause
license and attribution. This private integration is intended for direct local
use, not Mac App Store distribution. Release publishing, notarization, signing
identities, and update infrastructure are outside the prototype scope.
