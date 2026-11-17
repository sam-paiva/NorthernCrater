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
                            isPaused: viewModel.pausedDownloads.contains(mod.id),
                            onDownload: {
                                Task { await viewModel.downloadAndInstall(mod, into: modManager) }
                            },
                            onPause: { viewModel.pause(mod) },
                            onResume: { viewModel.resume(mod, into: modManager) },
                            onCancel: { viewModel.cancel(mod) }
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
    let isPaused: Bool
    let onDownload: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    
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
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: progress)
                            .frame(width: 150)
                        Text((isPaused ? "Paused • " : "") + progressText(progress))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button(action: isPaused ? onResume : onPause) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(isPaused ? "Resume download" : "Pause download")
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel download")
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
    
    /// "0.7% • 20 MB of 2.8 GB": a big mod on a slow mirror would sit at "1%" and look stuck.
    private func progressText(_ progress: Double) -> String {
        let percent = progress < 0.1 ? String(format: "%.1f%%", progress * 100) : "\(Int(progress * 100))%"
        guard let kb = mod.fileSizeKB, kb > 0 else { return percent }
        let total = Int64(kb) * 1024
        let done = Int64(progress * Double(total))
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(percent) • \(f.string(fromByteCount: done)) of \(f.string(fromByteCount: total))"
    }
    
    private var formattedSize: String {
        guard let kb = mod.fileSizeKB, kb > 0 else { return "" }
        let mb = Double(kb) / 1024.0
        return String(format: " • %.1f MB", mb)
    }
}
