import Foundation
import Observation
import AppKit

/// Asks GitHub for the newest release and tells the user when it is newer than this app.
/// It never downloads or installs anything: the button opens the release page.
@Observable
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    
    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let notes: String
    }
    
    static let repository = "sam-paiva/NorthernCrater"
    
    /// A newer release the user has not skipped.
    private(set) var available: Release?
    private(set) var isChecking = false
    /// Set only by a manual check: "up to date" or the reason it failed.
    var manualResult: String?
    
    @ObservationIgnored private let defaults = UserDefaults.standard
    private let skippedKey = "UpdateChecker.skippedVersion"
    private let lastCheckKey = "UpdateChecker.lastCheck"
    
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    
    /// At launch: at most one check a day, and silent when there is nothing new or no network.
    func checkInBackground() async {
        if let last = defaults.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        _ = try? await check(ignoreSkipped: false)
    }
    
    /// From the menu: always asks, ignores a skipped version, and reports the outcome.
    func checkManually() async {
        manualResult = nil
        do {
            if try await check(ignoreSkipped: true) == nil {
                manualResult = "NorthernCrater \(currentVersion) is the latest version."
            }
        } catch {
            manualResult = "Could not check for updates: \(error.localizedDescription)"
        }
    }
    
    func skip(_ release: Release) {
        defaults.set(release.version, forKey: skippedKey)
        available = nil
    }
    
    func openDownloadPage(_ release: Release) {
        NSWorkspace.shared.open(release.pageURL)
    }
    
    @discardableResult
    private func check(ignoreSkipped: Bool) async throws -> Release? {
        guard !isChecking else { return available }
        isChecking = true
        defer { isChecking = false }
        
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NorthernCrater", forHTTPHeaderField: "User-Agent")   // GitHub requires one
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CatalogError.downloadFailed("GitHub returned HTTP \(http.statusCode)")
        }
        defaults.set(Date(), forKey: lastCheckKey)
        
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let body: String?
            let draft: Bool?
            let prerelease: Bool?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        
        guard payload.draft != true, payload.prerelease != true,
              Self.isNewer(version, than: currentVersion) else {
            available = nil
            return nil
        }
        if !ignoreSkipped, defaults.string(forKey: skippedKey) == version {
            available = nil
            return nil
        }
        let release = Release(version: version, pageURL: payload.html_url, notes: payload.body ?? "")
        available = release
        return release
    }
    
    /// "1.10.0" > "1.9" by numeric parts; anything non-numeric counts as 0.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
