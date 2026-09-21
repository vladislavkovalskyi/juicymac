# Juicy Mac — notes for future sessions

Personal project of Vladislav. **No Jira, no ticket keys** — but keep writing design notes under
`docs/dev/NNN-topic/README.md` before large changes.

## Build and test

```bash
cd JuicyKit && swift test                                   # fast: pure logic + live samplers
xcodegen generate                                           # after ANY file added or removed
xcodebuild -project JuicyMac.xcodeproj -scheme JuicyMac \
  -sdk macosx -configuration Debug -derivedDataPath build build
```

- `xcode-select` points at CommandLineTools on this machine and its SDK is broken. Always export
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (and `SDKROOT=$(xcrun --sdk macosx --show-sdk-path)`
  for SwiftPM) or pass `-sdk macosx` to xcodebuild.
- Signing: team `SHFR8S4R37`, automatic. The helper's Info.plist carries `JMTeamIdentifier`, which the
  helper uses to build its code-signing requirement — change both together.

## Running and screenshotting the app

- The window opens automatically only on first launch (`defaultLaunchBehavior`). To force it:
  `defaults delete com.kovalskyi.JuicyMac` before launching.
- `JUICY_MODULE=fans` (DEBUG only) opens straight to a module — handy for screenshots.
- Screenshot only the app window, never the whole desktop:
  raise it with System Events, read `position`/`size`, then `screencapture -R"x,y,w,h"`.
  The script used during development lives in the session scratchpad; recreate it as needed.
- The popover cannot be opened by AppleScript clicks; check it by hand.

## Architecture

`SamplingEngine` (actor) → `Snapshot` (Sendable) → `AppModel` (@MainActor, @Observable) → views.
Anything pure goes in `JuicyCore` so it can be unit tested; anything touching IOKit goes in
`JuicySystem`.

Gotchas found the hard way:

- SMC integer types decode big-endian; `flt ` is little-endian. `.map(Double.init)` silently picks
  `Double(bitPattern:)` — always write `.map { Double($0) }`.
- Battery capacities live in the nested `BatteryData` dictionary on Apple silicon, and the registry
  has no battery temperature: take it from the SMC `TB*` sensors.
- Reading all ~226 SMC keys every second costs real CPU. `SensorSampler.sensors(full:)` refreshes a
  small fast set each tick and everything else every fifth tick.
- Number formatting must pass `Fmt.locale` (en_US), or the system locale sneaks in ("2 324" vs "2,324").
- Charts: thin history to ~200 points (`AppModel.points`), and render the menu bar image once per
  sample in the model, not inside the view's body.
- Module screens can exceed the window height: keep them inside the `ScrollView` with
  `.defaultScrollAnchor(.top)`.

## Design

- Liquid Glass over a per-module `MeshGradient`. One background per window; the sidebar is a glass
  panel on top of it, never a second gradient.
- Type and spacing come from `App/Design/Typography.swift` (`JuicyFont`, `Space`). Don't invent sizes.
- 3D icons are rendered in Blender: `blender -b -P design/icons/render_icons.py -- design/icons/out`,
  then `python3 design/icons/make_assets.py` rebuilds the asset catalog and the app icon.
  Alternative fan colourways live in `design/icons/out/fan_{ice,juice,mint}.png`.

## Fan control

The app never writes to the SMC. `FanClient` (app) talks XPC to `JuicyMacHelper` (root), which
clamps targets, raises `Ftst` when the chip needs it, and resets fans to automatic on a 30-second
watchdog or when the connection drops. Test fan writes only with the user's explicit go-ahead.
