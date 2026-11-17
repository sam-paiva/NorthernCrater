//
//  RecompilationService.swift
//  NorthernCrater
//

import Foundation

enum RecompilationError: LocalizedError {
    case missingToolchain(String)
    case missingGameExecutable
    case missingBuildResource(String)
    case subprocessFailed(step: String, exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .missingToolchain(let tool):
            return "Required build tool '\(tool)' not found. Install the Xcode Command Line Tools (xcode-select --install) and Homebrew packages: cmake, ninja, python."
        case .missingGameExecutable:
            return "Could not find ff7/resources/ff7_1.02/ff7_en in the selected folder. Select \"FINAL FANTASY VII Steam Edition\" (not the 2013 Edition)."
        case .missingBuildResource(let name):
            return "Bundled build file '\(name)' is missing from the app bundle."
        case .subprocessFailed(let step, let code):
            return "Build failed during '\(step)' (exit code \(code)). Check the build log for details."
        }
    }
}

protocol Recompiling {
    func buildNativeApp(from steamGameDirectory: URL) -> AsyncThrowingStream<String, Error>
    /// Lifts the enabled mods' code patches into the engine (reads the mod profile at `profile`).
    func optimizeForMods(profile: URL) -> AsyncThrowingStream<String, Error>
}

/// Builds the native macOS engine from the `engine/` sources bundled in the app (a copy of GJ Materia's
/// engine, GPL-3.0: see engine/NOTICE.md) and the player's own copy of the game. The work is done by
/// `build_engine.sh`, also bundled; this type checks the tools, runs it and streams its output.
struct RecompilationService: Recompiling {

    func buildNativeApp(from steamGameDirectory: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    guard FileManager.default.fileExists(
                        atPath: LiveGameService.exeURL(in: steamGameDirectory).path) else {
                        throw RecompilationError.missingGameExecutable
                    }

                    // 1. Toolchain
                    continuation.yield("▶ Verifying the build toolchain (git, cmake, ninja, python3, clang)...")
                    for tool in ["git", "cmake", "ninja", "python3", "clang"] {
                        let path = try resolveExecutable(tool)
                        continuation.yield("  \(tool): \(path)")
                    }

                    // 2. The bundled build script and the engine sources
                    guard let scriptURL = Bundle.main.url(forResource: "build_engine", withExtension: "sh") else {
                        throw RecompilationError.missingBuildResource("build_engine.sh")
                    }
                    guard let sourcesURL = Bundle.main.url(forResource: "engine", withExtension: nil) else {
                        throw RecompilationError.missingBuildResource("engine/")
                    }
                    
                    // 3. Sync, build, stage (15-30 minutes the first time, quick afterwards)
                    try AppPaths.ensureDirectoriesExist()
                    try FileManager.default.createDirectory(at: AppPaths.engineDirectory, withIntermediateDirectories: true)
                    try FileManager.default.createDirectory(at: AppPaths.gameDirectory, withIntermediateDirectories: true)
                    try await runCommand(
                        executable: "/bin/bash",
                        arguments: [
                            scriptURL.path,
                            sourcesURL.path,
                            AppPaths.engineDirectory.path,
                            steamGameDirectory.path,
                            AppPaths.gameDirectory.path
                        ],
                        workingDirectory: AppPaths.engineDirectory,
                        continuation: continuation
                    )

                    guard FileManager.default.isExecutableFile(atPath: AppPaths.engineExecutable.path) else {
                        throw RecompilationError.subprocessFailed(step: "engine app (not produced)", exitCode: 1)
                    }
                    continuation.yield("✅ Build complete: \(AppPaths.engineApp.path)")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func optimizeForMods(profile: URL) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    guard let scriptURL = Bundle.main.url(forResource: "relift_mods", withExtension: "sh") else {
                        throw RecompilationError.missingBuildResource("relift_mods.sh")
                    }
                    try await runCommand(
                        executable: "/bin/bash",
                        arguments: [scriptURL.path, AppPaths.engineDirectory.path, profile.path],
                        workingDirectory: AppPaths.engineDirectory,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    private func resolveExecutable(_ name: String) throws -> String {
        let searchPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        if let found = searchPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return found
        }
        throw RecompilationError.missingToolchain(name)
    }

    private func runCommand(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        try await withCheckedThrowingContinuation { (checked: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory

            // Homebrew first, so cmake finds ninja and python3 is the Homebrew one
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            func emit(_ data: Data) {
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(whereSeparator: \.isNewline) {
                    continuation.yield(String(line))
                }
            }

            pipe.fileHandleForReading.readabilityHandler = { handle in
                emit(handle.availableData)
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                emit(pipe.fileHandleForReading.readDataToEndOfFile())   // whatever was still buffered
                if proc.terminationStatus == 0 {
                    checked.resume()
                } else {
                    checked.resume(throwing: RecompilationError.subprocessFailed(
                        step: URL(fileURLWithPath: executable).lastPathComponent,
                        exitCode: proc.terminationStatus
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                checked.resume(throwing: error)
            }
        }
    }
}
