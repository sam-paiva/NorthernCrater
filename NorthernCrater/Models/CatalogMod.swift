import Foundation

struct CatalogMod: Identifiable, Hashable, Codable {
    let id: String // Mod GUID from catalog XML
    let name: String
    let author: String
    let version: String
    let category: String
    let description: String
    let downloadURLs: [URL] // Resolved HTTP/HTTPS mirrors
    let fileSizeKB: Int?
    let previewImageURL: URL?
}
