import Foundation

final class RuntimeInspectorLogStream {
    private let process: Process
    private let pipe: Pipe

    init(deviceUDID: String, onLine: @escaping @Sendable (String) -> Void) {
        process = Process()
        pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "simctl", "spawn", deviceUDID, "log", "stream",
            "--style", "compact",
            "--level", "debug",
            "--predicate", "eventMessage CONTAINS \"[RuntimeInspector]\"",
        ]
        process.standardOutput = pipe
        process.standardError = pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                onLine(line)
            }
        }
    }

    func start() throws {
        try process.run()
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }
}

enum RuntimeInspectorService {
    private static let sourceFilePath = #filePath

    static func buildDylib() throws -> String {
        let root = try repoRoot()
        let script = root.appendingPathComponent("Scripts/build_runtime_inspector.sh")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw NSError(
                domain: "RuntimeInspectorService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing runtime inspector build script at \(script.path)"]
            )
        }

        let output = try run(
            executable: "/bin/bash",
            arguments: [script.path],
            currentDirectory: root
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func launch(bundleID: String, deviceUDID: String, dylibPath: String) throws {
        let root = try repoRoot()
        _ = try? run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "terminate", deviceUDID, bundleID],
            currentDirectory: root
        )

        try setLaunchEnvironment(
            name: "DYLD_INSERT_LIBRARIES",
            value: dylibPath,
            deviceUDID: deviceUDID,
            root: root
        )
        defer {
            try? unsetLaunchEnvironment(
                name: "DYLD_INSERT_LIBRARIES",
                deviceUDID: deviceUDID,
                root: root
            )
        }

        _ = try run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "launch", deviceUDID, bundleID],
            currentDirectory: root
        )
    }

    static func repoRoot() throws -> URL {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if FileManager.default.fileExists(atPath: cwd.appendingPathComponent("Package.swift").path) {
            return cwd
        }

        var sourceCandidate = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: sourceCandidate.appendingPathComponent("Package.swift").path) {
                return sourceCandidate
            }
            sourceCandidate.deleteLastPathComponent()
        }

        var candidate = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw NSError(
            domain: "RuntimeInspectorService",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not locate repo root. Current directory: \(cwd.path). Source path: \(sourceFilePath)"
            ]
        )
    }

    private static func run(executable: String, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "RuntimeInspectorService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: error.isEmpty ? output : error]
            )
        }

        return output
    }

    private static func setLaunchEnvironment(name: String, value: String, deviceUDID: String, root: URL) throws {
        _ = try run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "spawn", deviceUDID, "launchctl", "setenv", name, value],
            currentDirectory: root
        )
    }

    private static func unsetLaunchEnvironment(name: String, deviceUDID: String, root: URL) throws {
        _ = try run(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "spawn", deviceUDID, "launchctl", "unsetenv", name],
            currentDirectory: root
        )
    }
}
