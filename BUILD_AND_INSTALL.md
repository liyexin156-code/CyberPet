# Build and Install

This project is a Swift Package that can still run from the terminal for smoke tests, and can now be packaged as a standard macOS `.app` bundle for normal use.

## Build the app

```sh
cd /Users/liyexin/Documents/Codex/2026-05-29/files-mentioned-by-the-user-prd-3
bash Tools/package-app.sh
```

The script prefers `/Applications/Xcode.app` when present and keeps the Clang module cache inside `.build/module-cache`.

The script builds release binaries and creates:

```text
.build/app/PetTaskBuddy.app
```

The bundle layout is:

```text
PetTaskBuddy.app/
  Contents/
    Info.plist
    MacOS/PetTaskBuddy
    Resources/pet/
```

`Info.plist` sets `LSUIElement = true`, so the app runs as an accessory agent: no Dock icon, no normal menu bar focus, and no terminal window.

## Install

Copy the app into `/Applications` or `~/Applications`:

```sh
cp -R .build/app/PetTaskBuddy.app /Applications/
```

Then double-click `PetTaskBuddy.app`.

If macOS Gatekeeper blocks the first launch because this is locally built and ad-hoc signed, open it from Finder with Control-click > Open, or run:

```sh
xattr -dr com.apple.quarantine /Applications/PetTaskBuddy.app
```

The app does not need Accessibility permission for its current drag/click behavior. If future features control other apps or read global UI state, macOS may ask for Accessibility permission in System Settings.

## Login Item

On macOS 13 and newer, the app calls `SMAppService.mainApp.register()` on launch. This is the preferred login-item mechanism. Registration is skipped when running the raw SwiftPM executable from the terminal, because login items must point at an `.app` bundle.

If registration fails, the error is logged with `NSLog`. Common causes are running from a transient build path, moving the app after registering, or system policy blocking login items. For best results, install the app in `/Applications` or `~/Applications`, launch it once, then check System Settings > General > Login Items.

## Older macOS LaunchAgent fallback

For older systems, copy the sample LaunchAgent and load it:

```sh
mkdir -p ~/Library/LaunchAgents
cp Packaging/com.liyexin.PetTaskBuddy.launchagent.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.liyexin.PetTaskBuddy.launchagent.plist
launchctl enable gui/$(id -u)/com.liyexin.PetTaskBuddy
```

If you install the app somewhere other than `/Applications/PetTaskBuddy.app`, edit `ProgramArguments` in the plist first.

Difference: `SMAppService` is the modern user-visible Login Items API and is managed by macOS. A LaunchAgent is a lower-level launchd job; it can keep the process alive, but the plist path and executable path must be maintained manually.
