//
//  ModManagerServices.swift
//  NorthernCrater
//

import Foundation

enum ModManagerError: LocalizedError {
    case invalidSteamDirectory
    case legacyEdition
    case nativeBinaryMissing

    var errorDescription: String? {
        switch self {
        case .invalidSteamDirectory:
            return "Invalid folder: pick the main folder of \"FINAL FANTASY VII Steam Edition\" (it contains ff7/resources/ff7_1.02 and ff7/workingdir/data)."
        case .legacyEdition:
            return "This is the 2013 Edition. Install \"FINAL FANTASY VII\" (the new release, listed as \"FINAL FANTASY VII Steam Edition\" on disk; free for 2013 owners) and select its folder instead."
        case .nativeBinaryMissing:
            return "The native engine has not been built yet. Press Build first."
        }
    }
}

protocol GameManaging {
    func validateSteamDirectory(_ url: URL) throws -> Bool
    func prepareGameDirectory(from steamDirectory: URL) throws -> URL
    func writeModProfile(mods: [ModItem]) throws
    func writeFFNxConfig(config: GameLaunchConfig, mods: [ModItem]) throws
    func launchGame(in gameDir: URL, config: GameLaunchConfig) throws
}

protocol IROParsing {
    func parseMod(at url: URL) throws -> ModItem
}

struct LiveGameService: GameManaging {
    /// The 1.02 US exe and the game data inside the new Steam release.
    static func exeURL(in steamDirectory: URL) -> URL {
        steamDirectory.appendingPathComponent("ff7/resources/ff7_1.02/ff7_en")
    }

    static func dataURL(in steamDirectory: URL) -> URL {
        steamDirectory.appendingPathComponent("ff7/workingdir/data")
    }

    /// Checks the folder; returns whether the native engine has already been built.
    func validateSteamDirectory(_ url: URL) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: Self.exeURL(in: url).path),
              fm.fileExists(atPath: Self.dataURL(in: url).path) else {
            // The 2013 Edition keeps ff7_en.exe next to FF7_Launcher.exe and is not supported.
            if fm.fileExists(atPath: url.appendingPathComponent("FF7_Launcher.exe").path) {
                throw ModManagerError.legacyEdition
            }
            throw ModManagerError.invalidSteamDirectory
        }
        return fm.isExecutableFile(atPath: AppPaths.engineExecutable.path)
    }

    /// Points the engine's game folder at the current Steam install: a fresh copy of the 1.02 exe and
    /// a link to the game data. (The build staged the rest: FFNx settings and shaders.)
    func prepareGameDirectory(from steamDirectory: URL) throws -> URL {
        let fm = FileManager.default
        let gameDir = AppPaths.gameDirectory
        guard fm.fileExists(atPath: gameDir.appendingPathComponent("shaders").path) else {
            throw ModManagerError.nativeBinaryMissing   // not staged: the engine has not been built
        }
        let exeDest = gameDir.appendingPathComponent("ff7_en.exe")
        try? fm.removeItem(at: exeDest)
        try fm.copyItem(at: Self.exeURL(in: steamDirectory), to: exeDest)

        let dataLink = gameDir.appendingPathComponent("data")
        try? fm.removeItem(at: dataLink)
        try fm.createSymbolicLink(at: dataLink, withDestinationURL: Self.dataURL(in: steamDirectory))
        return gameDir
    }

    /// The engine reads `<game folder>/../mods/profile.xml`, the app's `mods` folder (see ModProfileWriter).
    func writeModProfile(mods: [ModItem]) throws {
        let conditions = AppPaths.engineDirectory
            .appendingPathComponent("src/external/7th-Heaven/AppUI/Resources/7thHeaven.var")
        try ModProfileWriter.write(mods: mods, to: AppPaths.modsDirectory, conditionsFile: conditions)
    }

    /// The game folder's FFNx.toml: the player's settings plus what the enabled mods ask for.
    func writeFFNxConfig(config: GameLaunchConfig, mods: [ModItem]) throws {
        try FFNxConfigWriter.write(gameDirectory: AppPaths.gameDirectory, config: config, mods: mods)
    }

    /// Starts the engine (it has no launcher of its own) in the app's game folder and home.
    func launchGame(in gameDir: URL, config: GameLaunchConfig) throws {
        let binaryURL = AppPaths.engineExecutable
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw ModManagerError.nativeBinaryMissing
        }
        try FileManager.default.createDirectory(at: AppPaths.engineHome, withIntermediateDirectories: true)
        let logURL = AppPaths.engineHome.appendingPathComponent("last_run.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)

        var env = ProcessInfo.processInfo.environment
        // Running the app from Xcode turns on Metal's debug layer, which the game would inherit: it aborts on
        // harmless issues (an unbound texture sampler) that a normal run ignores. The game never gets it.
        for key in env.keys where key.hasPrefix("MTL_") || key == "METAL_DEVICE_WRAPPER_TYPE" || key == "METAL_DEBUG_ERROR_MODE" {
            env[key] = nil
        }
        env["FF7_GAME_DIR"] = gameDir.path
        env["FF7_QUICKBOOT"] = nil              // the game always opens on its title screen
        env["FF7_LOG_STDERR"] = "1"
        env["FF7_ASPECT"] = String(config.aspectCode)
        env["FF7_SWAP_AB"] = config.swapConfirmCancel ? "1" : "0"

        let process = Process()
        process.executableURL = binaryURL
        process.environment = env
        process.currentDirectoryURL = gameDir
        process.standardOutput = log
        process.standardError = log
        try process.run()
    }
}
