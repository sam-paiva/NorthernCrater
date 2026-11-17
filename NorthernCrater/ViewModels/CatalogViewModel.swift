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
    var errorMessage: String?
    
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
        
        do {
            let localIRO = try await catalogService.downloadMod(mod) { value in
                Task { @MainActor in
                    self.downloadProgress[mod.id] = value
                }
            }
            modManager.importMods([localIRO])
            downloadProgress.removeValue(forKey: mod.id)
        } catch {
            downloadProgress.removeValue(forKey: mod.id)
            errorMessage = "Failed to download \(mod.name): \(error.localizedDescription)"
        }
    }
}
