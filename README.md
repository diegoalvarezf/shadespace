# Shadespace

A native macOS app that turns the MacBook notch into a small, quiet island. It stays hidden inside the notch and opens when you hover over it.

## Features

- **Now Playing**: Spotify and Apple Music with artwork, play/pause, skip, shuffle, repeat and seeking. Swipe horizontally over the island to change track. The system volume slider follows the current output, keyboard volume keys included.
- **Synced lyrics**: the current line follows the song, from [LRCLib](https://lrclib.net).
- **Drop a file on the notch**: three zones appear.
  - **Summarize**: on-device summaries of PDFs, text and Word documents, plus questions about them, using Apple Intelligence. Nothing leaves the Mac.
  - **Convert**: PNG ↔ JPG, and HEIC, WebP, TIFF or GIF to PNG/JPG. The original is never overwritten.
  - **AirDrop**: send the files to a nearby device.
  - **Tray**: keep files for later, drag them out into any app or AirDrop them.
- **Pomodoro**: 15, 25 or 50-minute focus sessions with short breaks and a long break every fourth session. While it runs, the countdown sits beside the notch and the pixel bot reacts to it: it blinks while you focus, bounces on breaks, dozes when paused and celebrates when a session ends.
- **Claude Code sessions**: connect Claude Code from the menu and, while an agent works, the pixel bot shows a line describing the current step (for example "Edit · RootView.swift +12 −3"). It types while working, raises a "!" when the agent needs you, and celebrates when it's done. An Agents page lists every session and its last step. Hooks are added to `~/.claude/settings.json` next to your existing ones, after a backup, and are sent only to a local server on `127.0.0.1`.
- **Pixel bot companion**: a small pixel bot lives beside the camera, on one side of the notch. It blinks, glances around, ducks behind the camera, crosses to the other side, waves hello, dances to music and falls asleep after 10 minutes without input or when it's worn out. Its mood and energy drift over time, grow with finished Pomodoros, finished agent sessions and music, and recover while it sleeps. When the island opens it strolls along the strip below the header, with its mood and energy on the right. Show it or hide it, and pick its color, from the menu.
- **Alerts**: charger connected, low battery, fully charged, AirPods connected with their battery levels.
- **Home**: clock, date and local weather when nothing is playing.
- **Any display**: on Macs without a notch or on an external monitor, the island opens from the top edge of the screen.

Settings live in the menu bar icon: lyrics, weather units, alerts, the bot and its color, an optional activity strip below the notch, and launch at login.

## Requirements

- macOS 14 or later
- AI summaries need macOS 26 with Apple Intelligence turned on. Without it, Shadespace shows an excerpt of the document instead.

## Privacy

- No accounts, analytics or telemetry.
- Music is read locally from Spotify and Music through Apple Events.
- Summaries run on the Mac's on-device model.
- Claude Code hook events are received on `127.0.0.1` only and need a per-install token; nothing is reachable from the network.
- Network requests are limited to lyrics (song title, artist, album and duration sent to LRCLib) and weather (location rounded to about 1 km, sent to [Open-Meteo](https://open-meteo.com)). Both can be turned off.

macOS asks for permission the first time Shadespace controls Spotify or Music, reads your location for weather, and uses Bluetooth for AirPods.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Shadespace.xcodeproj -scheme Shadespace -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Shadespace.app
```

Run the tests:

```bash
xcodebuild test -project Shadespace.xcodeproj -scheme Shadespace -derivedDataPath build
```

Signing uses the development team set in `project.yml`. Change `DEVELOPMENT_TEAM` to your own to build it yourself.

## Project layout

```
Sources/Shadespace/
  App/        App entry point and menu bar menu
  Window/     Notch panel, geometry, hover tracking and file drops
  State/      Island state, settings and module registry
  UI/         Island views and shared components
  Modules/    NowPlaying, AI, Files, Tray, Share, Pomodoro, Agents, Companion,
              Battery, AirPods, Weather
Tests/        Unit tests
```

## License

[MIT](LICENSE)
