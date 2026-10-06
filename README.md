# LastWindow

A macOS menu bar app that quits an app when you close its last window, the way Windows does.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or Command Line Tools)

## Build and install

```sh
./build.sh
open ~/Applications/LastWindow.app
```

`build.sh` builds a release binary, wraps it in `LastWindow.app`, signs it ad-hoc, and installs it to `~/Applications`. On first launch macOS asks for Accessibility permission, which LastWindow needs to see other apps' windows. It starts watching as soon as you grant it.

Each build gets a new ad-hoc signature, so macOS drops the old Accessibility grant. `build.sh` resets it for you, so expect to grant permission again after every rebuild.

## Usage

LastWindow runs in the menu bar (window icon) and has no Dock icon. The menu has:

- **Accessibility** status. If permission is missing, click it to open System Settings.
- **Enabled**: turn auto-quit on or off.
- **Launch at Login**
- **Open Config…** / **Reload Config**
- **Quit LastWindow**

## Configuration

The config lives at `~/Library/Application Support/LastWindow/config.json` and is created on first launch. List the bundle identifiers of apps that should never be auto-quit:

```json
{
  "excluded": [
    "com.apple.Terminal",
    "com.spotify.client"
  ]
}
```

To find an app's bundle identifier, run `osascript -e 'id of app "Safari"'`. Choose **Reload Config** after you edit the file.

Finder and LastWindow itself are always excluded.

## How it works

LastWindow watches every regular app through the Accessibility API. When one of an app's windows is destroyed, it waits 500 ms so a window that closes and is immediately replaced doesn't count, then checks whether any standard windows are left. It quits the app only if all of these are true:

- auto-quit is enabled and the app isn't excluded
- the app has shown at least one standard window since LastWindow began watching it, so apps that launch without a window are left alone
- Accessibility reports no standard windows (minimized windows still count as open)
- none of the app's previously seen windows still exist on another Space
- none of the app's windows that are assigned to All Desktops are still open. Slack and Teams only hide these windows when you close them, and around screen lock and unlock Accessibility can stop listing them, so they count as closed only when the screen is unlocked and the window is off screen.

Accessibility only lists windows on the current Space. To catch windows on other Spaces, LastWindow remembers every window ID it has seen and asks the window server (via the private SkyLight APIs that yabai and AltTab also use) whether those windows are still alive and which Space they're on.

## Development

```sh
./test.sh
```

The decision logic lives in `LastWindowCore` (`QuitPolicy`, `WindowCount`, `Config`) and is unit-tested. The AppKit and Accessibility code is in `Sources/LastWindow`. `test.sh` wraps `swift test` and adds the plugin path that Command Line Tools need for swift-testing.

Logs go to the unified log under the subsystem `com.adamstahl.LastWindow`:

```sh
log stream --predicate 'subsystem == "com.adamstahl.LastWindow"'
```
