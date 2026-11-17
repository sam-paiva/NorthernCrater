import Foundation
import Observation

@Observable
@MainActor
final class CatalogViewModel {
    var selectedFeedURL: URL = CatalogService.defaultFeedURLs[0].url
    var customFeedInput: String = ""
    var allMods: [CatalogMod] = []
    var searchText: String = ""
    var selectedCategory: String = "All"
    
    var isLoadingFeed: Bool = false
    var downloadProgress: [String: Double] = [:] // mod.id -> 0.0...1.0
    var pausedDownloads: Set<String> = []        // mod ids
    var errorMessage: String?
    
    private enum StopReason { case pause, cancel }
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var stopReasons: [String: StopReason] = [:]
    @ObservationIgnored private let catalogService: any CatalogManaging
    
    init(catalogService: any CatalogManaging = CatalogService()) {
        self.catalogService = catalogService
    }
    
    var availableCategories: [String] {
        let cats = Set(allMods.map(\.category))
        return ["All"] + cats.sorted()
    }
    
    var filteredMods: [CatalogMod] {
        allMods.filter { mod in
            let matchesCategory = (selectedCategory == "All") || (mod.category == selectedCategory)
            let matchesSearch = searchText.isEmpty ||
                mod.name.localizedCaseInsensitiveContains(searchText) ||
                mod.author.localizedCaseInsensitiveContains(searchText) ||
                mod.description.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }
    
    func loadCatalog() async {
        isLoadingFeed = true
        errorMessage = nil
        do {
            allMods = try await catalogService.fetchCatalog(from: selectedFeedURL)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingFeed = false
    }
    
    func addCustomFeed() async {
        guard let url = URL(string: customFeedInput.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.hasPrefix("http") == true else {
            errorMessage = "Enter a valid HTTP/HTTPS XML catalog URL."
            return
        }
        selectedFeedURL = url
        await loadCatalog()
    }
    
    func downloadAndInstall(_ mod: CatalogMod, into modManager: ModManagerViewModel) async {
        guard downloadProgress[mod.id] == nil else { return }
        downloadProgress[mod.id] = 0.01
        errorMessage = nil
        start(mod, into: modManager, after: nil)
    }
    
    func pause(_ mod: CatalogMod) {
        guard let task = downloadTasks[mod.id], !pausedDownloads.contains(mod.id) else { return }
        pausedDownloads.insert(mod.id)
        stopReasons[mod.id] = .pause
        task.cancel()
    }
    
    func resume(_ mod: CatalogMod, into modManager: ModManagerViewModel) {
        guard pausedDownloads.contains(mod.id) else { return }
        pausedDownloads.remove(mod.id)
        stopReasons[mod.id] = nil
        // The paused task may still be winding down (flushing its last bytes): wait for it.
        start(mod, into: modManager, after: downloadTasks[mod.id])
    }
    
    /// Stops the download (running or paused) and deletes the partial file.
    func cancel(_ mod: CatalogMod) {
        pausedDownloads.remove(mod.id)
        if let task = downloadTasks[mod.id] {
            stopReasons[mod.id] = .cancel
            task.cancel()
        } else {
            catalogService.discardPartialDownload(for: mod)
            downloadProgress.removeValue(forKey: mod.id)
        }
    }
    
    private func start(_ mod: CatalogMod, into modManager: ModManagerViewModel, after previous: Task<Void, Never>?) {
        downloadTasks[mod.id] = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let localIRO = try await self.catalogService.downloadMod(mod) { value in
                    Task { @MainActor in
                        if self.downloadProgress[mod.id] != nil { self.downloadProgress[mod.id] = value }
                    }
                }
                modManager.importMods([localIRO])
                self.finish(mod)
            } catch {
                let stopped = error is CancellationError || (error as? URLError)?.code == .cancelled
                if stopped {
                    switch self.stopReasons.removeValue(forKey: mod.id) {
                    case .pause:
                        self.downloadTasks[mod.id] = nil   // partial file kept, progress stays on screen
                    default:
                        self.catalogService.discardPartialDownload(for: mod)
                        self.finish(mod)
                    }
                } else {
                    self.finish(mod)
                    self.errorMessage = "Failed to download \(mod.name): \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func finish(_ mod: CatalogMod) {
        downloadTasks[mod.id] = nil
        pausedDownloads.remove(mod.id)
        downloadProgress.removeValue(forKey: mod.id)
    }
}
