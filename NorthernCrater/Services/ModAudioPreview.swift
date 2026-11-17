//
//  ModAudioPreview.swift
//  NorthernCrater
//
//  Plays the sound previews some mods ship (`PreviewAudio="…"` on an option choice; Symphonic Remasters has 93).
//  They are Ogg Vorbis, which macOS cannot play, so the track is converted to a temporary WAV by `ogg2wav`
//  (built once from the libvorbis sources the engine build downloads) and played with AVAudioPlayer.
//

import AVFoundation
import Foundation
import Observation

nonisolated enum AudioPreviewError: LocalizedError {
    case needsEngine, unreadable, conversionFailed

    var errorDescription: String? {
        switch self {
        case .needsEngine: return "Sound previews need the engine to be built once: it provides the sound decoder."
        case .unreadable: return "The sound file could not be read from the mod."
        case .conversionFailed: return "The sound file could not be decoded."
        }
    }
}

/// Converting is slow-ish file and process work: kept off the main actor.
nonisolated enum AudioPreviewConverter {
    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NorthernCraterPreviews", isDirectory: true)
    }

    static func clearOldFiles() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Makes sure the helper exists (building it the first time) and returns it.
    private static func helper(buildScript: URL, source: URL) throws -> URL {
        let engine = AppPaths.engineDirectory
        let tool = engine.appendingPathComponent("bin/ogg2wav")
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: tool.path),
           let built = (try? fm.attributesOfItem(atPath: tool.path))?[.modificationDate] as? Date,
           let changed = (try? fm.attributesOfItem(atPath: source.path))?[.modificationDate] as? Date,
           built >= changed { return tool }
        guard fm.fileExists(atPath: engine.appendingPathComponent("src/external/deps/vorbis/lib/vorbisfile.c").path) else {
            throw AudioPreviewError.needsEngine
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [buildScript.path, source.path, engine.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, fm.isExecutableFile(atPath: tool.path) else {
            throw AudioPreviewError.conversionFailed
        }
        return tool
    }

    /// A WAV for the Ogg `data`; `key` names the cached file so a track is converted once.
    static func wav(for data: Data, key: String, buildScript: URL, source: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let wav = folder.appendingPathComponent(key + ".wav")
        if fm.fileExists(atPath: wav.path) { return wav }
        let tool = try helper(buildScript: buildScript, source: source)
        let ogg = folder.appendingPathComponent(key + ".ogg")
        try data.write(to: ogg)
        defer { try? fm.removeItem(at: ogg) }
        let process = Process()
        process.executableURL = tool
        process.arguments = [ogg.path, wav.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? fm.removeItem(at: wav)
            throw AudioPreviewError.conversionFailed
        }
        return wav
    }
}

@MainActor
@Observable
final class ModAudioPreview: NSObject, AVAudioPlayerDelegate {
    static let shared = ModAudioPreview()

    /// Identifies the track being prepared or played (mod + path).
    private(set) var preparingKey: String?
    private(set) var playingKey: String?
    private(set) var errorMessage: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var request = 0

    static func key(modURL: URL, path: String) -> String { modURL.path + "|" + path }

    func isBusy(_ key: String) -> Bool { preparingKey == key || playingKey == key }

    /// Starts the track, or stops it if it is the one playing.
    func toggle(modURL: URL, path: String) {
        let key = Self.key(modURL: modURL, path: path)
        let wasThis = isBusy(key)
        stop()
        if wasThis { return }
        request += 1
        let mine = request
        preparingKey = key
        errorMessage = nil
        let script = Bundle.main.url(forResource: "build_ogg2wav", withExtension: "sh")
        let source = Bundle.main.url(forResource: "engine", withExtension: nil)?.appendingPathComponent("tools/ogg2wav.c")
        Task {
            do {
                guard let script, let source else { throw AudioPreviewError.conversionFailed }
                guard let data = await ModPreviewStore.shared.data(modURL: modURL, path: path) else { throw AudioPreviewError.unreadable }
                let name = String(format: "%016llx", UInt64(truncatingIfNeeded: key.hashValue)) + "\(data.count)"
                let wav = try await Task.detached(priority: .userInitiated) {
                    try AudioPreviewConverter.wav(for: data, key: name, buildScript: script, source: source)
                }.value
                guard mine == request else { return }          // the player moved on to something else
                let player = try AVAudioPlayer(contentsOf: wav)
                player.delegate = self
                self.player = player
                preparingKey = nil
                playingKey = key
                player.play()
            } catch {
                guard mine == request else { return }
                preparingKey = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        request += 1
        player?.stop()
        player = nil
        preparingKey = nil
        playingKey = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.player = nil; self.playingKey = nil }
        }
    }
}
