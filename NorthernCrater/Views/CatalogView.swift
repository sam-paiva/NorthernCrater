import SwiftUI

struct CatalogView: View {
    @Bindable var modManager: ModManagerViewModel
    @State private var viewModel = CatalogViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Feed & Category Filter Bar
                HStack(spacing: 12) {
                    Picker("Catalog", selection: $viewModel.selectedFeedURL) {
                        ForEach(CatalogService.defaultFeedURLs, id: \.url) { feed in
                            Text(feed.name).tag(feed.url)
                        }
                    }
                    .frame(width: 220)
                    .onChange(of: viewModel.selectedFeedURL) { _, _ in
                        Task { await viewModel.loadCatalog() }
                    }
                    
                    Picker("Category", selection: $viewModel.selectedCategory) {
                        ForEach(viewModel.availableCategories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .frame(width: 180)
                    
                    Spacer()
                    
                    Button {
                        Task { await viewModel.loadCatalog() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingFeed)
                }
                .padding()
                .background(.bar)
                
                Divider()
                
                // Main Catalog List
                if viewModel.isLoadingFeed {
                    Spacer()
                    ProgressView("Fetching 7th Heaven Catalog…")
                    Spacer()
                } else if let error = viewModel.errorMessage, viewModel.allMods.isEmpty {
                    ContentUnavailableView(
                        "Catalog Unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else {
                    List(viewModel.filteredMods) { mod in
                        CatalogModRow(
                            mod: mod,
                            isInstalled: modManager.mods.contains {
                                $0.name.localizedCaseInsensitiveCompare(mod.name) == .orderedSame
                            },
                            progress: viewModel.downloadProgress[mod.id],
                            onDownload: {
                                Task { await viewModel.downloadAndInstall(mod, into: modManager) }
                            }
                        )
                    }
                    .listStyle(.inset)
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search mods, authors, categories…")
            .navigationTitle("7th Heaven Mod Catalog")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if viewModel.allMods.isEmpty {
                    await viewModel.loadCatalog()
                }
            }
        }
        .frame(minWidth: 740, minHeight: 520)
    }
}

private struct CatalogModRow: View {
    let mod: CatalogMod
    let isInstalled: Bool
    let progress: Double?
    let onDownload: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(mod.name)
                        .font(.headline)
                    Text(mod.category)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                
                Text("by \(mod.author) • v\(mod.version)\(formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if !mod.description.isEmpty {
                    Text(mod.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            if let progress {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: progress)
                        .frame(width: 90)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Download", action: onDownload)
                    .buttonStyle(.bordered)
                    .disabled(mod.downloadURLs.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var formattedSize: String {
        guard let kb = mod.fileSizeKB, kb > 0 else { return "" }
        let mb = Double(kb) / 1024.0
        return String(format: " • %.1f MB", mb)
    }
}
