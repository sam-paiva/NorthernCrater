//
//  ModPreviewStore.swift
//  NorthernCrater
//
//  Loads the preview pictures mods ship (`<PreviewFile>` for the mod, `PreviewFile="…"` on each option
//  choice) from an .iro or a mod folder, off the main thread, as screen-sized thumbnails. Results are
//  cached; a missing or unreadable picture is remembered too, so it is not retried on every redraw.
//  Animated GIFs show their first frame.
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated struct PreviewImage: @unchecked Sendable {
    let cgImage: CGImage
}

actor ModPreviewStore {
    static let shared = ModPreviewStore()

    private var archives: [URL: IROArchive] = [:]
    private var cache: [String: PreviewImage?] = [:]
    private var order: [String] = []
    private let capacity = 80

    /// The picture at `path` (as written in mod.xml, either slash) inside the mod, or nil.
    func image(modURL: URL, path: String, maxPixels: Int = 900) -> PreviewImage? {
        let key = modURL.path + "\u{0}" + path
        if let hit = cache[key] { return hit }
        let loaded = load(modURL: modURL, path: path, maxPixels: maxPixels)
        cache[key] = .some(loaded)
        order.append(key)
        if order.count > capacity { cache[order.removeFirst()] = nil }
        return loaded
    }

    /// The raw bytes of a file inside the mod (for the sound previews).
    func data(modURL: URL, path: String) -> Data? {
        readData(modURL: modURL, path: path)
    }

    private func load(modURL: URL, path: String, maxPixels: Int) -> PreviewImage? {
        guard let data = readData(modURL: modURL, path: path), !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return PreviewImage(cgImage: image)
    }

    private func readData(modURL: URL, path: String) -> Data? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modURL.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            let root = BinaryIROParser.modRoot(in: modURL) ?? modURL
            var url = root
            for part in path.replacingOccurrences(of: "\\", with: "/").split(separator: "/") where part != "." {
                url.appendPathComponent(String(part))
            }
            return try? Data(contentsOf: url)
        }
        do {
            let archive: IROArchive
            if let known = archives[modURL] {
                archive = known
            } else {
                archive = try IROArchive(url: modURL)
                archives[modURL] = archive
            }
            guard let entry = archive.entry(named: path) else { return nil }
            return try archive.read(entry)
        } catch {
            return nil
        }
    }
}
