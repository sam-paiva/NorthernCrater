import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ModManagerViewModel {
    // MARK: - View State
    var steamGameDirectory: URL? {
        didSet { persistState() }
    }
    var isGameValidated: Bool = false
    var isRecompiled: Bool = false
    var isBuilding: Bool = false
    /// True while the engine is being re-lifted for the enabled mods (a couple of minutes).
    var isOptimizing: Bool = false
    var buildLogLines: [String] = []
    
    var mods: [ModItem] = [] {
        didSet { persistState() }
    }
    var selectedModID: UUID?
    /// What the last import could not add (shown in an alert).
    var importIssues: [String] = []
    var launchConfig = GameLaunchConfig() {
        didSet { persistState() }
    }
    var statusMessage: String = "Select your Steam FINAL FANTASY VII folder to begin."
    
    // MARK: - Dependencies
    @ObservationIgnored private let gameService: any GameManaging
    @ObservationIgnored private let iroParser: any IROParsing
    @ObservationIgnored private let recompiler: any Recompiling
    @ObservationIgnored private let persistence: any StatePersisting
    @ObservationIgnored private var isRestoringState = false
    
    init(
        gameService: any GameManaging = LiveGameService(),
        iroParser: any IROParsing = BinaryIROParser(),
        recompiler: any Recompiling = RecompilationService(),
        persistence: any StatePersisting = StatePersistenceService()
    ) {
        self.gameService = gameService
        self.iroParser = iroParser
        self.recompiler = recompiler
        self.persistence = persistence
        AudioPreviewConverter.clearOldFiles()   // sound previews converted in an earlier run
        restorePersistedState()
    }
    
    var selectedModIndex: Int? {
        mods.firstIndex { $0.id == selectedModID }
    }
    
    var activeModCount: Int {
        mods.filter(\.isEnabled).count
    }
    
    // MARK: - Persistence
    
    private func restorePersistedState() {
        isRestoringState = true
        defer { isRestoringState = false }
        
        guard let saved = try? persistence.load() else { return }
        
        launchConfig = saved.launchConfig
        
        // Restore mods whose .iro files still exist on disk, keeping exact load order & options
        var validMods = saved.mods.filter { FileManager.default.fileExists(atPath: $0.archiveURL.path) }
        // State saved before FFNx settings were read: fill them in from the mod itself (options stay as saved).
        for i in validMods.indices where (validMods[i].infoVersion ?? 0) < ModItem.currentInfoVersion {
            guard let fresh = try? iroParser.parseMod(at: validMods[i].archiveURL) else { continue }
            validMods[i].ffnxConfig = fresh.ffnxConfig ?? []
            validMods[i].previewFile = fresh.previewFile
            for o in validMods[i].options.indices {
                guard let freshOption = fresh.options.first(where: { $0.id == validMods[i].options[o].id }) else { continue }
                for c in validMods[i].options[o].choices.indices {
                    let id = validMods[i].options[o].choices[c].id
                    let freshChoice = freshOption.choices.first { $0.id == id }
                    validMods[i].options[o].choices[c].previewFile = freshChoice?.previewFile
                    validMods[i].options[o].choices[c].previewAudio = freshChoice?.previewAudio
                }
            }
            validMods[i].infoVersion = ModItem.currentInfoVersion
        }
        mods = validMods
        selectedModID = validMods.first?.id
        
        if let savedPath = saved.steamGamePath {
            selectSteamFolder(URL(fileURLWithPath: savedPath, isDirectory: true), shouldPersist: false)
        }
    }
    
    private func persistState() {
        guard !isRestoringState else { return }
        let snapshot = PersistedAppState(
            steamGamePath: steamGameDirectory?.path,
            mods: mods,
            launchConfig: launchConfig
        )
        try? persistence.save(snapshot)
    }
    
    // MARK: - User Intents
    
    func selectSteamFolder(_ url: URL, shouldPersist: Bool = true) {
        if !shouldPersist {
            // Restoring at launch: remember the path in memory without writing, even if validation fails below.
            isRestoringState = true
            steamGameDirectory = url
            isRestoringState = false
        }
        do {
            let compiled = try gameService.validateSteamDirectory(url)
            if shouldPersist { steamGameDirectory = url }
            
            isGameValidated = true
            isRecompiled = compiled
            statusMessage = compiled
                ? "Ready to play (\(activeModCount) active mod(s))."
                : "Steam FF7 verified. Ready to build native macOS binary."
        } catch {
            // On launch, keep the saved path (e.g. drive unmounted) so it isn't wiped from disk.
            if shouldPersist { steamGameDirectory = nil }
            isGameValidated = false
            isRecompiled = false
            statusMessage = error.localizedDescription
        }
    }
    
    /// Adds any number of mods in one go: .iro archives and unpacked mod folders (a folder with a mod.xml,
    /// or a wrapper folder around one). A bad file never stops the others; what could not be added is listed
    /// in `importIssues` and the status bar says what happened.
    func importMods(_ urls: [URL]) {
        var added = 0, duplicates = 0
        var issues: [String] = []
        var seen = Set<URL>()
        
        for url in urls {
            let key = url.standardizedFileURL
            guard seen.insert(key).inserted else { continue }
            
            let ext = url.pathExtension.lowercased()
            if ["7z", "zip", "rar"].contains(ext) {
                issues.append("\(url.lastPathComponent): archives like .\(ext) are not read directly. Unpack it and add the .iro file or the mod folder.")
                continue
            }
            if mods.contains(where: { $0.archiveURL.standardizedFileURL == key }) {
                duplicates += 1
                continue
            }
            do {
                let parsed = try iroParser.parseMod(at: url)
                // A folder may turn out to be a mod we already have (same inner folder)
                if mods.contains(where: { $0.archiveURL.standardizedFileURL == parsed.archiveURL.standardizedFileURL }) {
                    duplicates += 1
                    continue
                }
                mods.append(parsed)
                if selectedModID == nil { selectedModID = parsed.id }
                added += 1
            } catch {
                issues.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        var parts: [String] = []
        if added > 0 { parts.append("added \(added) mod\(added == 1 ? "" : "s")") }
        if duplicates > 0 { parts.append("\(duplicates) already in the list") }
        if !issues.isEmpty { parts.append("\(issues.count) not added") }
        statusMessage = parts.isEmpty ? "Nothing to add." : parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst() + "."
        importIssues = issues
    }
    
    func removeMods(at offsets: IndexSet) {
        let removedIDs = offsets.map { mods[$0].id }
        mods.remove(atOffsets: offsets)
        if let selected = selectedModID, removedIDs.contains(selected) {
            selectedModID = mods.first?.id
        }
    }
    
    func moveMods(from source: IndexSet, to destination: Int) {
        mods.move(fromOffsets: source, toOffset: destination)
    }
    
    func buildNativeBinary() {
        guard let gameDir = steamGameDirectory, !isBuilding else { return }
        
        isBuilding = true
        buildLogLines.removeAll()
        statusMessage = "Building the native engine (first time: 15-30 minutes)..."
        
        Task {
            do {
                for try await line in recompiler.buildNativeApp(from: gameDir) {
                    buildLogLines.append(line)
                    if buildLogLines.count > 250 {
                        buildLogLines.removeFirst(buildLogLines.count - 250)
                    }
                }
                isRecompiled = true
                isBuilding = false
                statusMessage = "Native engine built. Ready to play."
            } catch {
                isBuilding = false
                buildLogLines.append("❌ \(error.localizedDescription)")
                statusMessage = error.localizedDescription
            }
        }
    }
    
    func playGame() {
        guard let gameDir = steamGameDirectory, !isOptimizing, !isBuilding else { return }
        Task {
            do {
                let gameFolder = try gameService.prepareGameDirectory(from: gameDir)
                try gameService.writeModProfile(mods: mods)
                // The config goes first: mods pick their code patches by FFNx settings (e.g. the aspect ratio),
                // and the re-lift reads it.
                try gameService.writeFFNxConfig(config: launchConfig, mods: mods)
                var note = ""
                if ModOptimizer.needsOptimizing(for: mods, config: launchConfig) {
                    note = await optimizeEngineForMods()
                }
                try gameService.launchGame(in: gameFolder, config: launchConfig)
                statusMessage = "FF7 started with \(activeModCount) active mod(s)." + note
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    /// Re-lifts the engine for the enabled mods so their code patches run natively. A failure is not fatal:
    /// the game still starts, only slower. Returns a note for the status line when something went wrong.
    private func optimizeEngineForMods() async -> String {
        isOptimizing = true
        defer { isOptimizing = false }
        statusMessage = "Optimizing the game for your mods so battles run fast (about 2 minutes, only when mods change)..."
        buildLogLines.removeAll()
        let mods = self.mods, config = self.launchConfig
        do {
            for try await line in recompiler.optimizeForMods(profile: AppPaths.modsDirectory.appendingPathComponent("profile.xml")) {
                buildLogLines.append(line)
                if buildLogLines.count > 250 { buildLogLines.removeFirst(buildLogLines.count - 250) }
            }
            ModOptimizer.markOptimized(for: mods, config: config)
            return ""
        } catch {
            buildLogLines.append("❌ \(error.localizedDescription)")
            return " (Optimizing for mods failed, so battles may be slow: \(error.localizedDescription))"
        }
    }
    
    private static let categoryPriority: [String: Int] = [
        "Driver": 0,
        "Gameplay": 1,
        "Overhaul": 2,
        "Textures": 3,
        "Model": 4,
        "Translation": 5,
        "UI": 6,
        "Audio": 7,
        "Cheat": 8,
        "Uncategorized": 9
    ]

    /// Auto-sorts enabled mods according to standard 7th Heaven category priority ranks
    func autoSortModsByPriority() {
        mods.sort { mod1, mod2 in
            let rank1 = Self.categoryPriority[mod1.category] ?? 50
            let rank2 = Self.categoryPriority[mod2.category] ?? 50
            if rank1 != rank2 {
                return rank1 < rank2
            }
            return mod1.name < mod2.name
        }
        statusMessage = "Mods auto-sorted by category priority."
    }

    /// Identifies active categories that have more than one enabled mod (potential conflict)
    var categoryConflicts: [String] {
        let enabledCategories = mods.filter(\.isEnabled).map(\.category)
        let counts = Dictionary(enabledCategories.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.filter { $0.value > 1 }.keys.sorted()
    }
}
