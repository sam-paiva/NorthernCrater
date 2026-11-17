import Foundation

struct ModOptionChoice: Identifiable, Hashable, Codable {
    let id: String                          // Option Value (e.g., "0", "1")
    let name: String                        // Display name (e.g., "60 FPS Battles")
    var subFolder: String? = nil            // Conditional folder inside .iro (e.g., "60fps")
    var tomlOverrides: [String: String] = [:] // Optional FFNx.toml key/value overrides
    var previewFile: String? = nil          // Picture inside the mod showing this choice (PreviewFile="…")
    var previewAudio: String? = nil         // Sound inside the mod for this choice (PreviewAudio="…")
}

/// One `<FFNxConfig>` entry of a mod.xml: an FFNx.toml key the mod sets, only while every option in `when`
/// (option ID -> value) has the given value. A list value is its items joined with commas.
struct FFNxEntry: Hashable, Codable {
    let key: String
    let value: String
    var when: [String: String] = [:]
}

struct ModOption: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let description: String
    var choices: [ModOptionChoice]
    var selectedChoiceId: String
    
    var selectedChoice: ModOptionChoice? {
        choices.first { $0.id == selectedChoiceId }
    }
}

struct ModItem: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var author: String
    var version: String
    var category: String
    var archiveURL: URL
    var isEnabled: Bool
    var options: [ModOption]
    var extractedHextDirectory: URL? = nil  // Cached .txt hext patches extracted from .iro
    /// The FFNx.toml settings this mod asks for. nil = not read yet (state saved by an older version).
    var ffnxConfig: [FFNxEntry]? = nil
    /// The mod's own picture (`<PreviewFile>`).
    var previewFile: String? = nil
    /// Which version of the parser read this mod's info; older saved state is read again (see `currentInfoVersion`).
    var infoVersion: Int? = nil
    static let currentInfoVersion = 3
}
