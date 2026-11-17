import Foundation

struct PersistedAppState: Codable {
    var steamGamePath: String?
    var mods: [ModItem]
    var launchConfig: GameLaunchConfig
}

protocol StatePersisting {
    func save(_ state: PersistedAppState) throws
    func load() throws -> PersistedAppState?
}

struct StatePersistenceService: StatePersisting {
    private var stateFileURL: URL {
        AppPaths.applicationSupport.appendingPathComponent("state.json")
    }
    
    func save(_ state: PersistedAppState) throws {
        try AppPaths.ensureDirectoriesExist()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: [.atomic])
    }
    
    func load() throws -> PersistedAppState? {
        guard FileManager.default.fileExists(atPath: stateFileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: stateFileURL)
        return try JSONDecoder().decode(PersistedAppState.self, from: data)
    }
}
