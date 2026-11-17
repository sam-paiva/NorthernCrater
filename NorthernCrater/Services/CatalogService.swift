import Foundation

enum CatalogError: LocalizedError {
    case invalidFeedURL
    case malformedCatalogXML
    case noValidDownloadMirror
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFeedURL:
            return "Invalid 7th Heaven catalog URL."
        case .malformedCatalogXML:
            return "Could not parse the 7th Heaven XML catalog feed."
        case .noValidDownloadMirror:
            return "This mod has no direct HTTP/HTTPS download mirror available."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}

protocol CatalogManaging {
    func fetchCatalog(from feedURL: URL) async throws -> [CatalogMod]
    func downloadMod(_ mod: CatalogMod, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

struct CatalogService: CatalogManaging {
    /// Default official 7th Heaven catalog subscription feeds
    static let defaultFeedURLs: [(name: String, url: URL)] = [
        ("Qhimm Catalog", URL(string: "https://github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/qhimm.xml")!),
        ("Sega Catalog", URL(string: "https://github.com/tsunamods-codes/7th-Heaven-Catalogs/releases/download/canary/sega.xml")!)
    ]
    
    func fetchCatalog(from feedURL: URL) async throws -> [CatalogMod] {
        let (data, response) = try await URLSession.shared.data(from: feedURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.downloadFailed("Catalog server returned HTTP \(http.statusCode)")
        }
        
        // Cache raw XML feed locally
        try? AppPaths.ensureDirectoriesExist()
        let cacheFile = AppPaths.catalogsDirectory.appendingPathComponent(feedURL.lastPathComponent.isEmpty ? "catalog.xml" : feedURL.lastPathComponent)
        try? data.write(to: cacheFile, options: .atomic)
        
        let delegate = CatalogXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        
        guard parser.parse() else {
            throw CatalogError.malformedCatalogXML
        }
        return delegate.mods
    }
    
    /// Keep the real archive type (.iro / .7z / .zip); Google Drive links carry no extension, so assume .iro.
    private static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ["iro", "7z", "zip"].contains(ext) ? ext : "iro"
    }
    
    func downloadMod(_ mod: CatalogMod, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let targetURL = mod.downloadURLs.first else {
            throw CatalogError.noValidDownloadMirror
        }
        
        try AppPaths.ensureDirectoriesExist()
        let safeFileName = mod.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-") + "." + Self.fileExtension(for: targetURL)
        let destinationURL = AppPaths.modsDirectory.appendingPathComponent(safeFileName)
        
        // Stream download with byte-level progress
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: targetURL)
        let expectedLength = response.expectedContentLength > 0
            ? Double(response.expectedContentLength)
            : Double((mod.fileSizeKB ?? 1024) * 1024)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }
        
        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var receivedBytes: Double = 0
        
        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                receivedBytes += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(min(receivedBytes / max(expectedLength, 1), 0.99))
            }
        }
        
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        progress(1.0)
        return destinationURL
    }
}

// MARK: - 7th Heaven Catalog XML Parser

private final class CatalogXMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var mods: [CatalogMod] = []
    
    private var inMod = false
    private var inLatestVersion = false
    private var currentText = ""
    
    private var id = ""
    private var name = ""
    private var author = "Unknown"
    private var version = "1.0"
    private var category = "Uncategorized"
    private var catalogDescription = ""
    private var links: [URL] = []
    private var fileSizeKB: Int?
    private var previewURL: URL?
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentText = ""
        if elementName == "LatestVersion" { inLatestVersion = true }
        if elementName == "Mod" {
            inMod = true
            inLatestVersion = false
            id = attributeDict["ID"] ?? UUID().uuidString
            name = ""
            author = "Unknown"
            version = "1.0"
            category = "Uncategorized"
            catalogDescription = ""
            links = []
            fileSizeKB = nil
            previewURL = nil
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard inMod else { return }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "ID":
            if !trimmed.isEmpty { id = trimmed }
        case "Name":
            name = trimmed
        case "Author":
            if !trimmed.isEmpty { author = trimmed }
        case "Version":
            if !trimmed.isEmpty { version = trimmed }
        case "Category":
            if !trimmed.isEmpty { category = trimmed }
        case "Description":
            catalogDescription = trimmed
        case "DownloadSize":
            fileSizeKB = Int(trimmed)
        case "PreviewImage":
            previewURL = URL(string: trimmed)
        case "LatestVersion":
            inLatestVersion = false
        case "Link":
            // Only links inside <LatestVersion> are downloads; the mod-level <Link> is a forum/homepage URL.
            if inLatestVersion, let resolved = Self.resolveIrosLink(trimmed) {
                links.append(resolved)
            }
        case "Mod":
            if !name.isEmpty {
                mods.append(
                    CatalogMod(
                        id: id,
                        name: name,
                        author: author,
                        version: version,
                        category: category,
                        description: catalogDescription,
                        downloadURLs: links,
                        fileSizeKB: fileSizeKB,
                        previewImageURL: previewURL
                    )
                )
            }
            inMod = false
        default:
            break
        }
        currentText = ""
    }
    
    /// Converts 7th Heaven `iros://Url/https$example.com/mod.iro` links into standard HTTPS URLs
    private static func resolveIrosLink(_ raw: String) -> URL? {
        if raw.hasPrefix("iros://Url/") {
            let stripped = String(raw.dropFirst("iros://Url/".count))
            let normalized = stripped
                .replacingOccurrences(of: "https$", with: "https://")
                .replacingOccurrences(of: "http$", with: "http://")
            return makeURL(normalized)
        }
        if raw.hasPrefix("iros://GDrive/") {
            let fileID = String(raw.dropFirst("iros://GDrive/".count))
            return makeURL("https://drive.usercontent.google.com/download?export=download&confirm=t&id=\(fileID)")
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return makeURL(raw)
        }
        return nil
    }
    
    /// Catalog paths contain spaces and brackets (e.g. "Catalog 4.0/[4xUpscale]Grimmy.7z").
    private static func makeURL(_ string: String) -> URL? {
        URL(string: string)
            ?? string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }
}
