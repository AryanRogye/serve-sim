// swift-tools-version: 5.9
import PackageDescription
import Foundation

let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Applications/Xcode.app/Contents/Developer"
let privateFrameworks = "\(developerDir)/Library/PrivateFrameworks"

let simulatorFrameworkFlags = [
    "-F/Library/Developer/PrivateFrameworks",
    "-F\(privateFrameworks)",
]

let package = Package(
    name: "SwiftSimStreamer",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SimStreamerCore",
            targets: ["SimStreamerCore"]
        ),
        .executable(
            name: "sim-stream-app",
            targets: ["SimStreamApp"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SimStreamerCore",
            swiftSettings: [
                .unsafeFlags(simulatorFrameworkFlags),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/PrivateFrameworks",
                    "-F\(privateFrameworks)",
                    "-Xlinker", "-rpath", "-Xlinker", "/Library/Developer/PrivateFrameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "\(privateFrameworks)",
                ]),
                .linkedFramework("CoreSimulator"),
                .linkedFramework("SimulatorKit"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
            ]
        ),
        .executableTarget(
            name: "SimStreamApp",
            dependencies: [
                "SimStreamerCore",
            ]
        ),
    ]
)
