//
//  ContentView.swift
//  NorthernCrater
//
// Views/ContentView.swift
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ModManagerViewModel()
    @State private var showFolderPicker = false
    @State private var showCatalog = false
    @State private var showSaves = false
    @State private var showSettings = false
    @State private var showControls = false
    
    /// The native open panel for mods: .iro files, or unpacked mod folders, several at once.
    private func chooseMods(folders: Bool) {
        let panel = NSOpenPanel()
        panel.message = folders
            ? "Choose one or more mod folders (each holds a mod.xml)"
            : "Choose one or more .iro mod files"
        panel.prompt = "Add"
        panel.canChooseFiles = !folders
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        if !folders, let iro = UTType(filenameExtension: "iro") {
            panel.allowedContentTypes = [iro]
        }
        panel.begin { response in
            if response == .OK { viewModel.importMods(panel.urls) }
        }
    }
    
    /// What the Play button does, or what is missing before it can.
    private var playHelp: String {
        if !viewModel.isGameValidated { return "Choose your Steam folder first" }
        if !viewModel.isRecompiled { return "Build the game engine first (home page)" }
        if viewModel.isBuilding || viewModel.isOptimizing { return "Wait until the current step finishes" }
        return "Start the game with your enabled mods and settings"
    }

    var body: some View {
        NavigationSplitView {
            ModSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
                // Drop .iro files and mod folders from Finder onto the list
                .dropDestination(for: URL.self) { urls, _ in
                    viewModel.importMods(urls)
                    return !urls.isEmpty
                }
        } detail: {
            if let idx = viewModel.selectedModIndex {
                ModDetailView(mod: $viewModel.mods[idx])
            } else {
                SetupDashboardView(viewModel: viewModel, showFolderPicker: $showFolderPicker)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.selectedModID = nil } label: {
                    Label("Home", systemImage: "house")
                }
                .help("Back to the home page: Steam folder, build and settings")
                .disabled(viewModel.selectedModID == nil)
                
                Button { showFolderPicker = true } label: {
                    Label("Steam Folder", systemImage: "folder")
                }
                .help("Choose your \"FINAL FANTASY VII\" Steam folder (the new release, not the 2013 Edition)")
                Menu {
                    Button("Add Mod Files…") { chooseMods(folders: false) }
                    Button("Add Mod Folders…") { chooseMods(folders: true) }
                } label: {
                    Label("Add Mods", systemImage: "plus")
                }
                .help("Add .iro mod files or unpacked mod folders (you can also drop them on the list)")
                
                Button { showCatalog = true } label: {
                    Label("Catalog", systemImage: "globe")
                }
                .help(viewModel.isGameValidated
                      ? "Browse and download mods from the online catalogs"
                      : "Browse and download mods (choose your Steam folder first)")
                .disabled(!viewModel.isGameValidated)
                .sheet(isPresented: $showCatalog) {
                    CatalogView(modManager: viewModel)
                }
                
                Button { showSaves = true } label: {
                    Label("Saves", systemImage: "tray.full")
                }
                .help("See your save files, import one from another copy of the game, or look inside one")
                .sheet(isPresented: $showSaves) {
                    SavesView()
                }
                
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Graphics and controls: resolution, aspect ratio, anti-aliasing, lighting, VSync, 60 FPS, analog movement")
                .sheet(isPresented: $showSettings) {
                    SettingsSheet(viewModel: viewModel)
                }
                
                Button { showControls = true } label: {
                    Label("Controls", systemImage: "gamecontroller")
                }
                .help("Keyboard layout and controller: remap keys, test buttons, tune the analog sticks")
                .sheet(isPresented: $showControls) {
                    ControlsView(viewModel: viewModel)
                }
                
                Button { viewModel.playGame() } label: {
                    Label("Play FF7", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help(playHelp)
                .disabled(!viewModel.isGameValidated || !viewModel.isRecompiled || viewModel.isBuilding || viewModel.isOptimizing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView(
                isReady: viewModel.isGameValidated,
                isBusy: viewModel.isOptimizing || viewModel.isBuilding,
                message: viewModel.statusMessage
            )
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { viewModel.selectSteamFolder(url) }
        }
        .alert("Some mods were not added", isPresented: Binding(
            get: { !viewModel.importIssues.isEmpty },
            set: { if !$0 { viewModel.importIssues = [] } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.importIssues.joined(separator: "\n"))
        }
    }
}

struct ModSidebarView: View {
    @Bindable var viewModel: ModManagerViewModel
    
    var body: some View {
        List(selection: $viewModel.selectedModID) {
            Section {
                ForEach($viewModel.mods) { $mod in
                    HStack {
                        Toggle("", isOn: $mod.isEnabled)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mod.name).fontWeight(.medium)
                                if viewModel.categoryConflicts.contains(mod.category) && mod.isEnabled {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .help("Conflict: Multiple active mods in '\(mod.category)' category.")
                                }
                            }
                            Text("\(mod.category) • v\(mod.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(mod.id)
                }
                .onMove(perform: viewModel.moveMods)
                .onDelete(perform: viewModel.removeMods)
            } header: {
                HStack {
                    Text("Load Order (Top = Highest Priority)")
                    Spacer()
                    Button("Auto-Sort") {
                        viewModel.autoSortModsByPriority()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct GraphicsSettingsSection: View {
    @Bindable var viewModel: ModManagerViewModel

    var body: some View {
        Section("3. Native Metal & Graphics Settings") {
                Picker("Internal Resolution", selection: $viewModel.launchConfig.internalResolutionScale) {
                    Text("1x (Original)").tag(1)
                    Text("2x").tag(2)
                    Text("4x (HD)").tag(4)
                }
                Picker("Aspect Ratio", selection: $viewModel.launchConfig.aspectRatio) {
                    Text("4:3 (Original)").tag("4:3")
                    Text("16:9 (Widescreen)").tag("16:9")
                    Text("16:10 (MacBook Display)").tag("16:10")
                    Text("21:9 (Ultrawide)").tag("21:9")
                }
                Toggle("60 FPS (a mod's own FPS option takes precedence)", isOn: $viewModel.launchConfig.enable60FPS)
                Toggle("Analog stick movement (360°)", isOn: $viewModel.launchConfig.analogControls)
                Picker("Anti-aliasing", selection: $viewModel.launchConfig.antialiasing) {
                    Text("Off").tag(0)
                    Text("2x").tag(2)
                    Text("4x").tag(4)
                    Text("8x").tag(8)
                    Text("16x").tag(16)
                }
                .help("Smooths jagged edges. Higher costs more GPU power.")
                Toggle("Real-time lighting and shadows", isOn: $viewModel.launchConfig.lighting)
                    .help("FFNx's lighting mode. Some mods (Cosmos Gaia) turn it on themselves. Costs GPU power.")
                Toggle("VSync", isOn: $viewModel.launchConfig.vsync)
                    .help("Waits for the screen's refresh before showing a frame: no tearing, a little more delay.")
                Toggle("Show FPS counter", isOn: $viewModel.launchConfig.showFPS)
            }
    }
}

struct SettingsSheet: View {
    @Bindable var viewModel: ModManagerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form { GraphicsSettingsSection(viewModel: viewModel) }
                .formStyle(.grouped)
            HStack {
                Text("Applied the next time you press Play.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 460, height: 420)
    }
}

struct SetupDashboardView: View {
    @Bindable var viewModel: ModManagerViewModel
    @Binding var showFolderPicker: Bool
    
    var body: some View {
        Form {
            Section("1. Steam Installation") {
                LabeledContent("Game Path") {
                    Text(viewModel.steamGameDirectory?.path ?? "Not selected")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Select FINAL FANTASY VII Folder…") {
                    showFolderPicker = true
                }
            }
            
            Section("2. Native macOS Runtime (Static Recompilation + Metal)") {
                LabeledContent("Binary Status") {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isRecompiled ? "checkmark.seal.fill" : "hammer.circle")
                            .foregroundStyle(viewModel.isRecompiled ? .green : .orange)
                        Text(viewModel.isRecompiled ? "Engine Ready" : "Not Built Yet")
                            .foregroundStyle(viewModel.isRecompiled ? .primary : .secondary)
                    }
                }
                
                HStack {
                    Button {
                        viewModel.buildNativeBinary()
                    } label: {
                        if viewModel.isBuilding {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Compiling Native Binary…")
                            }
                        } else {
                            Label(
                                viewModel.isRecompiled ? "Rebuild Engine" : "Build Engine",
                                systemImage: "cpu"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isGameValidated || viewModel.isBuilding)
                }
                
                if !viewModel.buildLogLines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(viewModel.buildLogLines.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(line.hasPrefix("❌") ? .red : .secondary)
                                        .textSelection(.enabled)
                                        .id(idx)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(height: 160)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: viewModel.buildLogLines.count) { _, newCount in
                            if newCount > 0 {
                                proxy.scrollTo(newCount - 1, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            GraphicsSettingsSection(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .navigationTitle("NorthernCrater — FF7 Mod Manager")
    }
}

struct StatusBarView: View {
    let isReady: Bool
    var isBusy = false
    let message: String
    
    var body: some View {
        HStack {
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Circle()
                    .fill(isReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(isBusy ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
