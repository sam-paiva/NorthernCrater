//
//  AppPath.swift
//  NorthernCrater
//

import Foundation

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("NorthernCrater", isDirectory: true)
    }
    
    /// The folder next to `Game/`: the engine reads `profile.xml` and the mods linked from it here, and
    /// catalog downloads land here too. (Lower case, as the engine spells it: macOS is usually
    /// case-insensitive, but not always.)
    static var modsDirectory: URL {
        applicationSupport.appendingPathComponent("mods", isDirectory: true)
    }
    
    static var buildCacheDirectory: URL {
        applicationSupport.appendingPathComponent("BuildCache", isDirectory: true)
    }
    
    /// The engine's sources and build (GJ Materia, built from the player's own game). It is outside
    /// "Application Support" on purpose: its build scripts break on a space in the path, and it can
    /// be rebuilt at any time.
    static var engineDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/NorthernCrater/engine", isDirectory: true)
    }
    
    /// The engine's app bundle once built.
    static var engineApp: URL {
        engineDirectory.appendingPathComponent("src/build/macos/NorthernCrater Engine.app", isDirectory: true)
    }
    
    static var engineExecutable: URL {
        engineApp.appendingPathComponent("Contents/MacOS/NorthernCrater Engine")
    }
    
    /// The folder the engine runs in (FF7_GAME_DIR): the 1.02 exe, a link to the game data, FFNx
    /// settings and shaders. The Steam install itself is never written to.
    static var gameDirectory: URL {
        applicationSupport.appendingPathComponent("Game", isDirectory: true)
    }
    
    /// Where the engine reads and writes the game's saves (saveNN.ff7).
    static var saveDirectory: URL {
        gameDirectory.appendingPathComponent("save", isDirectory: true)
    }
    
    /// Where the app keeps the engine's run logs (last_run.log).
    static var engineHome: URL {
        applicationSupport.appendingPathComponent("Engine", isDirectory: true)
    }
    
    static var catalogsDirectory: URL {
        applicationSupport.appendingPathComponent("Catalogs", isDirectory: true)
    }
    
    static func ensureDirectoriesExist() throws {
        let fm = FileManager.default
        for dir in [applicationSupport, modsDirectory, buildCacheDirectory, catalogsDirectory] {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
