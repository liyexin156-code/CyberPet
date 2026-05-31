# CyberPet

CyberPet is a small macOS desktop pet built with Swift, SwiftUI, SpriteKit, and SwiftData. It keeps a pixel dog on the desktop, tracks daily tasks, supports reminders, and reacts with idle, sleep, walk, sniff, run, and other pet animations.

## Features

- Desktop pet window with transparent background
- Pixel sprite animations loaded from `Assets/pet`
- Daily task list with completion tracking
- Thought bubble task view near the pet
- Reminder scheduling and notification support
- Pet state system with mood and fullness
- Local SwiftData persistence
- macOS app packaging script

## Requirements

- macOS 14 or newer
- Xcode installed at `/Applications/Xcode.app`
- Swift 5.9 or newer

## Build

```sh
swift build
```

## Run

```sh
swift run PetTaskBuddy
```

## Package App

```sh
bash Tools/package-app.sh
```

The packaged app is created at:

```text
.build/app/PetTaskBuddy.app
```

## Install

```sh
cp -R .build/app/PetTaskBuddy.app /Applications/
```

Then open `/Applications/PetTaskBuddy.app`.

## Install Test Build

1. Download `CyberPet.zip`.
2. Unzip the archive.
3. Drag `CyberPet.app` to Applications.
4. If macOS says it cannot verify the developer, right-click the app and choose Open.

## Tests

```sh
swift test
```

Smoke tests are also available:

```sh
swift run PetTaskBuddy --smoke-test-pet-state
swift run PetTaskBuddy --smoke-test-tasks
swift run PetTaskBuddy --smoke-test-schedule
swift run PetTaskBuddy --smoke-test-ai
```

## Project Structure

```text
Assets/pet/                 Pet sprite assets and animation manifest
Sources/PetTaskBuddy/       App source code
Tests/PetTaskBuddyTests/    XCTest coverage
Tools/package-app.sh        macOS app packaging script
Packaging/                  App bundle and LaunchAgent metadata
```

## Notes

CyberPet runs as a macOS accessory app, so it does not show a normal Dock icon. The packaged app uses `LSUIElement = true` in `Packaging/Info.plist`.
