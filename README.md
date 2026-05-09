# SwiftSimStreamer

This is a native SwiftUI macOS app built from the simulator streaming and
accessibility ideas in `serve-sim`.

This project contains code derived from Evan Bacon's `serve-sim`, which is
licensed under Apache-2.0. See [NOTICE](NOTICE) and [LICENSE](LICENSE).

It keeps only the pieces needed to capture a booted Apple Simulator and expose
frames to Swift:

- `FrameCapture`: attaches to CoreSimulator/SimulatorKit and reads the simulator
  framebuffer as `CVPixelBuffer` values.
- `JPEGVideoEncoder`: converts `CVPixelBuffer` frames into JPEG data.
- `SimulatorStreamer`: small reusable wrapper that coordinates capture,
  backpressure, screen-size changes, and JPEG delivery.
- `SimulatorAccessibility`: captures the frontmost simulator app's accessibility
  tree as labels, roles, values, enabled state, and screen-relative frames.
- `SimulatorInputController`: injects simulator touches and keyboard input.

The app renders the simulator stream natively and draws selectable accessibility
rectangles over the live image. The TypeScript CLI, React preview UI, browser
streaming server, WebSocket input, HID injection, Expo middleware, and agent
integrations are intentionally omitted.

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
