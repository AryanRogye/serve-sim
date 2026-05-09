import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

public final class SimulatorStreamer {
    public struct ScreenSize: Equatable, Sendable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    private let frameCapture = FrameCapture()
    private let encoder: JPEGVideoEncoder
    private let encodeQueue = DispatchQueue(label: "sim-streamer.encode", qos: .userInteractive)
    private let stateLock = NSLock()

    private var screenSize = ScreenSize(width: 0, height: 0)
    private var encoderReady = false
    private var encoding = false

    public init(jpegQuality: CGFloat = 0.7) {
        self.encoder = JPEGVideoEncoder(quality: jpegQuality)
    }

    public func start(
        deviceUDID: String,
        onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)? = nil,
        onJPEGFrame: @escaping (Data) -> Void,
        onScreenSize: ((ScreenSize) -> Void)? = nil
    ) throws {
        try frameCapture.start(deviceUDID: deviceUDID) { [weak self] pixelBuffer, timestamp in
            guard let self else { return }
            onPixelBuffer?(pixelBuffer, timestamp)

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            self.prepareEncoderIfNeeded(width: width, height: height, onJPEGFrame: onJPEGFrame, onScreenSize: onScreenSize)

            guard self.claimEncoder() else { return }
            self.encodeQueue.async {
                self.encoder.encode(pixelBuffer: pixelBuffer)
                self.releaseEncoder()
            }
        }
    }

    public func stop() {
        frameCapture.stop()
        encoder.stop()
    }

    public func currentScreenSize() -> ScreenSize? {
        guard let size = frameCapture.getScreenSize() else { return nil }
        return ScreenSize(width: size.width, height: size.height)
    }

    private func prepareEncoderIfNeeded(
        width: Int,
        height: Int,
        onJPEGFrame: @escaping (Data) -> Void,
        onScreenSize: ((ScreenSize) -> Void)?
    ) {
        stateLock.lock()
        let needsSetup = !encoderReady || screenSize.width != width || screenSize.height != height
        if needsSetup {
            screenSize = ScreenSize(width: width, height: height)
            encoderReady = true
        }
        let nextSize = screenSize
        stateLock.unlock()

        guard needsSetup else { return }

        encoder.stop()
        encoder.setup(width: Int32(width), height: Int32(height), fps: 60, onEncodedFrame: onJPEGFrame)
        onScreenSize?(nextSize)
    }

    private func claimEncoder() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard encoderReady, !encoding else { return false }
        encoding = true
        return true
    }

    private func releaseEncoder() {
        stateLock.lock()
        encoding = false
        stateLock.unlock()
    }
}
