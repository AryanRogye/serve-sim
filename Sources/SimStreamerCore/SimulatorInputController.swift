import CoreGraphics
import Darwin
import Foundation
import ObjectiveC

// Derived from serve-sim by Evan Bacon, licensed under Apache-2.0.
// Modified for SwiftSimStreamer as a direct Swift input controller.
//
public final class SimulatorInputController {
    public enum InputError: Error, LocalizedError {
        case deviceNotFound(String)
        case mouseInputUnavailable
        case keyboardInputUnavailable
        case hidClientUnavailable

        public var errorDescription: String? {
            switch self {
            case .deviceNotFound(let udid):
                return "Device \(udid) not found."
            case .mouseInputUnavailable:
                return "Simulator touch injection is unavailable."
            case .keyboardInputUnavailable:
                return "Simulator keyboard injection is unavailable."
            case .hidClientUnavailable:
                return "Simulator HID client is unavailable."
            }
        }
    }

    private var hidClient: NSObject?
    private var sendSelector: Selector?

    private typealias IndigoMouseFunc = @convention(c) (
        UnsafePointer<CGPoint>, UnsafePointer<CGPoint>?, UInt32, Int32, CGFloat, CGFloat, UInt32
    ) -> UnsafeMutableRawPointer?
    private var mouseFunc: IndigoMouseFunc?

    private typealias IndigoKeyboardFunc = @convention(c) (UInt32, UInt32) -> UnsafeMutableRawPointer?
    private var keyboardFunc: IndigoKeyboardFunc?

    private let inputQueue = DispatchQueue(label: "sim-streamer.input")

    public init() {}

    public func setup(deviceUDID: String) throws {
        _ = dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW)
        _ = dlopen("/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit", RTLD_NOW)

        guard let device = FrameCapture.findSimDevice(udid: deviceUDID) else {
            throw InputError.deviceNotFound(deviceUDID)
        }

        guard let mousePointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IndigoHIDMessageForMouseNSEvent") else {
            throw InputError.mouseInputUnavailable
        }
        mouseFunc = unsafeBitCast(mousePointer, to: IndigoMouseFunc.self)

        if let keyboardPointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IndigoHIDMessageForKeyboardArbitrary") {
            keyboardFunc = unsafeBitCast(keyboardPointer, to: IndigoKeyboardFunc.self)
        }

        guard let hidClass = NSClassFromString("_TtC12SimulatorKit24SimDeviceLegacyHIDClient") else {
            throw InputError.hidClientUnavailable
        }

        let initSelector = NSSelectorFromString("initWithDevice:error:")
        typealias HIDInitFunc = @convention(c) (
            AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>
        ) -> AnyObject?
        guard let initImplementation = class_getMethodImplementation(hidClass, initSelector) else {
            throw InputError.hidClientUnavailable
        }

        let initialize = unsafeBitCast(initImplementation, to: HIDInitFunc.self)
        var error: NSError?
        let client = initialize(hidClass.alloc(), initSelector, device, &error)
        if let error { throw error }
        guard let clientObject = client as? NSObject else {
            throw InputError.hidClientUnavailable
        }

        hidClient = clientObject
        sendSelector = NSSelectorFromString("sendWithMessage:freeWhenDone:completionQueue:completion:")
    }

    public func tap(x: Double, y: Double) {
        inputQueue.async { [weak self] in
            self?.sendTouch(type: "begin", x: x, y: y)
            Thread.sleep(forTimeInterval: 0.045)
            self?.sendTouch(type: "end", x: x, y: y)
        }
    }

    public func tap(element: AccessibilityElement, in snapshot: AccessibilitySnapshot) {
        guard snapshot.screen.width > 0, snapshot.screen.height > 0 else { return }
        let x = (element.frame.x + element.frame.width / 2) / snapshot.screen.width
        let y = (element.frame.y + element.frame.height / 2) / snapshot.screen.height
        tap(x: normalized(x), y: normalized(y))
    }

    public func typeText(_ text: String) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            for character in text {
                guard let stroke = KeyboardStroke(character: character) else { continue }
                self.send(stroke)
                Thread.sleep(forTimeInterval: 0.018)
            }
        }
    }

    public func pressReturn() {
        inputQueue.async { [weak self] in
            self?.sendKeyPress(usage: 0x28)
        }
    }

    public func pressBackspace(repeat count: Int = 1) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            for _ in 0..<max(0, count) {
                self.sendKeyPress(usage: 0x2A)
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
    }

    public func tapAndType(element: AccessibilityElement, in snapshot: AccessibilitySnapshot, text: String) {
        tap(element: element, in: snapshot)
        inputQueue.async { [weak self] in
            Thread.sleep(forTimeInterval: 0.18)
            self?.typeText(text)
        }
    }

    private func sendTouch(type: String, x: Double, y: Double) {
        guard let mouseFunc else { return }
        let eventType: Int32
        switch type {
        case "begin", "move":
            eventType = 1
        case "end":
            eventType = 2
        default:
            return
        }

        var point = CGPoint(x: normalized(x), y: normalized(y))
        guard let message = mouseFunc(&point, nil, 0x32, eventType, 1.0, 1.0, 0) else { return }
        send(message)
    }

    private func send(_ stroke: KeyboardStroke) {
        if stroke.requiresShift {
            sendKey(type: "down", usage: Self.leftShiftUsage)
        }
        sendKeyPress(usage: stroke.usage)
        if stroke.requiresShift {
            sendKey(type: "up", usage: Self.leftShiftUsage)
        }
    }

    private func sendKeyPress(usage: UInt32) {
        sendKey(type: "down", usage: usage)
        Thread.sleep(forTimeInterval: 0.008)
        sendKey(type: "up", usage: usage)
    }

    private func sendKey(type: String, usage: UInt32) {
        guard let keyboardFunc else { return }
        let direction: UInt32
        switch type {
        case "down":
            direction = 1
        case "up":
            direction = 2
        default:
            return
        }

        guard let message = keyboardFunc(usage, direction) else { return }
        send(message)
    }

    private func send(_ message: UnsafeMutableRawPointer) {
        guard let client = hidClient, let sendSelector else {
            free(message)
            return
        }

        typealias SendFunc = @convention(c) (
            AnyObject, Selector, UnsafeMutableRawPointer, ObjCBool, AnyObject?, AnyObject?
        ) -> Void
        guard let sendImplementation = class_getMethodImplementation(object_getClass(client), sendSelector) else {
            free(message)
            return
        }

        let sendMessage = unsafeBitCast(sendImplementation, to: SendFunc.self)
        sendMessage(client, sendSelector, message, ObjCBool(true), nil, nil)
    }

    private func normalized(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static let leftShiftUsage: UInt32 = 0xE1
}

private struct KeyboardStroke {
    let usage: UInt32
    let requiresShift: Bool

    init(usage: UInt32, requiresShift: Bool) {
        self.usage = usage
        self.requiresShift = requiresShift
    }

    init?(character: Character) {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return nil
        }
        self.init(scalar: scalar)
    }

    init?(scalar: Unicode.Scalar) {
        let value = scalar.value

        if value >= 65, value <= 90 {
            usage = UInt32(value - 65) + 0x04
            requiresShift = true
            return
        }

        if value >= 97, value <= 122 {
            usage = UInt32(value - 97) + 0x04
            requiresShift = false
            return
        }

        switch scalar {
        case "1": self = Self(usage: 0x1E, requiresShift: false)
        case "2": self = Self(usage: 0x1F, requiresShift: false)
        case "3": self = Self(usage: 0x20, requiresShift: false)
        case "4": self = Self(usage: 0x21, requiresShift: false)
        case "5": self = Self(usage: 0x22, requiresShift: false)
        case "6": self = Self(usage: 0x23, requiresShift: false)
        case "7": self = Self(usage: 0x24, requiresShift: false)
        case "8": self = Self(usage: 0x25, requiresShift: false)
        case "9": self = Self(usage: 0x26, requiresShift: false)
        case "0": self = Self(usage: 0x27, requiresShift: false)
        case "\n", "\r": self = Self(usage: 0x28, requiresShift: false)
        case "\t": self = Self(usage: 0x2B, requiresShift: false)
        case " ": self = Self(usage: 0x2C, requiresShift: false)
        case "-": self = Self(usage: 0x2D, requiresShift: false)
        case "=": self = Self(usage: 0x2E, requiresShift: false)
        case "[": self = Self(usage: 0x2F, requiresShift: false)
        case "]": self = Self(usage: 0x30, requiresShift: false)
        case "\\": self = Self(usage: 0x31, requiresShift: false)
        case ";": self = Self(usage: 0x33, requiresShift: false)
        case "'": self = Self(usage: 0x34, requiresShift: false)
        case "`": self = Self(usage: 0x35, requiresShift: false)
        case ",": self = Self(usage: 0x36, requiresShift: false)
        case ".": self = Self(usage: 0x37, requiresShift: false)
        case "/": self = Self(usage: 0x38, requiresShift: false)
        case "!": self = Self(usage: 0x1E, requiresShift: true)
        case "@": self = Self(usage: 0x1F, requiresShift: true)
        case "#": self = Self(usage: 0x20, requiresShift: true)
        case "$": self = Self(usage: 0x21, requiresShift: true)
        case "%": self = Self(usage: 0x22, requiresShift: true)
        case "^": self = Self(usage: 0x23, requiresShift: true)
        case "&": self = Self(usage: 0x24, requiresShift: true)
        case "*": self = Self(usage: 0x25, requiresShift: true)
        case "(": self = Self(usage: 0x26, requiresShift: true)
        case ")": self = Self(usage: 0x27, requiresShift: true)
        case "_": self = Self(usage: 0x2D, requiresShift: true)
        case "+": self = Self(usage: 0x2E, requiresShift: true)
        case "{": self = Self(usage: 0x2F, requiresShift: true)
        case "}": self = Self(usage: 0x30, requiresShift: true)
        case "|": self = Self(usage: 0x31, requiresShift: true)
        case ":": self = Self(usage: 0x33, requiresShift: true)
        case "\"": self = Self(usage: 0x34, requiresShift: true)
        case "~": self = Self(usage: 0x35, requiresShift: true)
        case "<": self = Self(usage: 0x36, requiresShift: true)
        case ">": self = Self(usage: 0x37, requiresShift: true)
        case "?": self = Self(usage: 0x38, requiresShift: true)
        default:
            return nil
        }
    }
}
