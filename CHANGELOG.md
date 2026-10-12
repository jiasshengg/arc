# Changelog

## 1.1.0

### Added

- A native settings window with island visibility, launch at login, display
  selection, idle hiding, hover expansion/delay, and battery alert controls.
- Browser media filtering and a configurable paused music timeout.
- Independent screenshot clipboard copying and island previews.
- Optional global shortcuts for Pocket and island visibility, with custom key
  recording, local persistence, and conflict handling.
- Menu Pocket arrangement help and Accessibility status in settings.
- About links and a confirmed Reset Settings action in a standalone footer.
- A styled drag-to-Applications DMG build script.

### Improved

- Hide the island temporarily while arranging Menu Pocket without changing its
  visibility preference or discarding held files. Arrange sits beside the Menu
  Bar heading in settings.
- Increase Menu Pocket row icons and hide its scrollbar while keeping scrolling.
- Attach the island to the top of external and mirrored displays, including
  closed-lid use, and restore disconnected display choices when reconnected.

### Fixed

- Preserve hover behavior when preferences change under a stationary pointer.
- Let ordinary clicks and non-file drags pass through a hidden island.
- Keep shortcut conflict errors visible when other registrations succeed.
- Distinguish paused recordings with identical titles and artists by album and
  duration so they receive their own visibility timeout.

### Compatibility

- macOS 14 or later. The downloadable build targets Apple Silicon.
- Local checks cover macOS 26; macOS 14 and Intel execution remain untested.
- Third-party Menu Pocket menu opening/restoration and physical display,
  keyboard, drag-and-drop, and permission flows still need hands-on testing.
- The app uses a local ad-hoc signature; notarization and automatic updates are
  not configured.
