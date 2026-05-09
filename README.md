

# SwiftSimStreamer

SwiftSimStreamer is a stripped-down native macOS SwiftUI app for looking inside
a booted Apple Simulator. It streams the simulator screen into a native window,
draws the simulator app's accessibility tree over the live image, lets you
select and tap visible elements, and includes an experimental runtime inspector
for logging UIKit target/action selectors from simulator apps.

The goal is to keep the interesting simulator pieces from `serve-sim`, but make
them easier to study from Swift:

- Native simulator framebuffer capture
- Native SwiftUI rendering instead of a browser preview
- Accessibility tree inspection and visual selection
- Simulator tap and keyboard injection
- A GUI-driven runtime selector logging experiment

## Demo



https://github.com/user-attachments/assets/f5f2113e-5250-4754-9f54-4de85bc47eb3



## Credit

This project is derived from Evan Bacon's [`serve-sim`](https://github.com/EvanBacon/serve-sim).
The original project and the public demo of simulator streaming, accessibility
selection, and iOS web debugging are the reason this exists.

`serve-sim` is licensed under Apache-2.0. This repository keeps that license and
includes attribution in [NOTICE](NOTICE) and [LICENSE](LICENSE).

This fork is not an upstream contribution to `serve-sim`. It is a substantially
modified local developer tool that removes the TypeScript CLI, React browser UI,
middleware, WebSocket server, npm workspace, and Expo-oriented integrations, then
adapts the simulator capture and inspection ideas into a SwiftPM-based macOS
SwiftUI app.

## What It Does

The app lists booted simulators in a sidebar. Select a simulator and press Start
to see its screen rendered in a native SwiftUI view. The app can refresh the
frontmost simulator app's accessibility tree, draw selectable rectangles over the
live image, show element details, and send real simulator taps or keyboard input
to selected elements.

The Runtime Inspector panel builds and injects a simulator-only dylib into one
target app at a time. When that app registers or fires UIKit controls and gesture
recognizers, the dylib logs selector information back into the GUI. This is
useful for learning how simulator apps are wired internally, especially when
combined with the visual accessibility overlay.

The core Swift modules are:

- `FrameCapture`: attaches to CoreSimulator/SimulatorKit and reads the simulator
  framebuffer as `CVPixelBuffer` values.
- `JPEGVideoEncoder`: converts `CVPixelBuffer` frames into JPEG data.
- `SimulatorStreamer`: coordinates capture, backpressure, screen-size changes,
  and JPEG delivery.
- `SimulatorAccessibility`: captures the frontmost simulator app's accessibility
  tree as labels, roles, values, enabled state, and screen-relative frames.
- `SimulatorInputController`: injects simulator touches and keyboard input.

The Runtime Inspector prototype lives in `RuntimeInspector/` and `Scripts/`.

## Requirements

- macOS 14+
- Xcode installed
- A booted iOS, iPadOS, or watchOS Simulator

This uses private Xcode frameworks:

- `CoreSimulator`
- `SimulatorKit`
- `IOSurface`

That is appropriate for a local developer tool, but not for App Store
distribution.

## Build

```sh
swift build
```

## Run the Native SwiftUI App

Boot a simulator first:

```sh
xcrun simctl list devices booted
```

Run:

```sh
swift run sim-stream-app
```

The app lists booted simulators in the sidebar. Select one, press Start, and it
will render the simulator stream natively with selectable accessibility
rectangles over the live image. The right panel lists the current AX elements
and shows details for the selected element.

Clicking an AX rectangle sends a real simulator tap at the center of that
element. The inspector also includes controls for Tap, Return, Delete, and
typing text into the selected element.

The Runtime Inspector panel can inject the selector-logging dylib into a
simulator app from the GUI. Enter a bundle id, press Inject & Launch, then tap
controls in the simulator. UIKit target/action and gesture logs appear in the
panel.

## Use From SwiftUI

For a native SwiftUI app, you probably do not need MJPEG. Use
`SimulatorStreamer` directly and render either the raw `CVPixelBuffer` frames
or the encoded JPEG data:

```swift
import SimStreamerCore

let streamer = SimulatorStreamer()

try streamer.start(
    deviceUDID: udid,
    onPixelBuffer: { pixelBuffer, timestamp in
        // Best path for SwiftUI/AppKit/Metal rendering.
    },
    onJPEGFrame: { jpegData in
        // Useful if you want an encoded stream or quick NSImage updates.
    },
    onScreenSize: { size in
        print("Simulator size:", size.width, size.height)
    }
)
```

Call `streamer.stop()` when the view model or window shuts down.

## Native Accessibility Selection

`SimulatorAccessibility.snapshot(deviceUDID:)` returns the same kind of data
that `serve-sim` uses for its AX overlay:

```swift
let snapshot = try SimulatorAccessibility.snapshot(deviceUDID: udid)

for element in snapshot.elements {
    print(element.label, element.role, element.frame)
}
```

To draw a SwiftUI overlay, scale from simulator coordinates into your rendered
image size:

```swift
let scaleX = renderedSize.width / snapshot.screen.width
let scaleY = renderedSize.height / snapshot.screen.height

let rect = CGRect(
    x: element.frame.x * scaleX,
    y: element.frame.y * scaleY,
    width: element.frame.width * scaleX,
    height: element.frame.height * scaleY
)
```

Render those rects in a `ZStack` above the simulator frame. Store the selected
`element.id` in your view model, and use a different stroke/fill for selected
or hovered elements.

## Native Input

`SimulatorInputController` wraps SimulatorKit HID injection:

```swift
let input = SimulatorInputController()
try input.setup(deviceUDID: udid)
input.tap(element: element, in: snapshot)
input.typeText("hello")
input.pressReturn()
```

## Runtime Selector Inspector

The `RuntimeInspector` prototype builds an iOS Simulator dylib that swizzles a
few UIKit dispatch points:

- `UIApplication.sendAction(_:to:from:for:)`
- `UIControl.addTarget(_:action:for:)`
- `UIControl.sendAction(_:to:for:)`
- `UIGestureRecognizer.init(target:action:)`
- `UIGestureRecognizer.addTarget(_:action:)`

Build it:

```sh
./Scripts/build_runtime_inspector.sh
```

You can use this from the native app's Runtime Inspector panel. For debugging,
you can also launch one simulator app from the command line:

```sh
./Scripts/launch_with_runtime_inspector.sh com.example.MyApp
```

Then interact with the app in Simulator or through `sim-stream-app`. Events are
logged with the `[RuntimeInspector]` prefix. To watch them from another terminal:

```sh
./Scripts/stream_runtime_inspector_logs.sh
```

This is simulator-only runtime instrumentation. Start with one app at a time;
injecting into SpringBoard or every simulator process can destabilize the
simulator.
