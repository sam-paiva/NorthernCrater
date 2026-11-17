//
//  SavesView.swift
//  NorthernCrater
//

import SwiftUI
import UniformTypeIdentifiers

struct SavesView: View {
    @State private var viewModel = SavesViewModel()
    @Environment(\.dismiss) private var dismiss
    
    /// The native open panel. (SwiftUI's fileImporter is unreliable inside a sheet when the window
    /// behind it already has one.)
    private func chooseFile(prompt: String, then handle: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true      // saves often sit in hidden or Library folders
        panel.begin { response in
            if response == .OK, let url = panel.url { handle(url) }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if let message = viewModel.message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                
                if let opened = viewModel.openedFile {
                    Section {
                        SaveFileRows(file: opened)
                        HStack {
                            Button("Import into Game") { viewModel.importOpenedFile() }
                                .buttonStyle(.borderedProminent)
                            Button("Close") { viewModel.closeOpenedFile() }
                        }
                    } header: {
                        Text("Opened file: \(opened.url.path)")
                    } footer: {
                        Text("Importing copies the file into the game's first free save file. Nothing is overwritten and the original is not changed.")
                    }
                }
                
                Section {
                    EmptyView()
                } footer: {
                    Text("Game save folder: \(AppPaths.saveDirectory.path)")
                        .textSelection(.enabled)
                }
                
                Section("In the game") {
                    if viewModel.gameSaves.isEmpty {
                        Text("No save files yet. Use Import Save File… to add one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.gameSaves) { file in
                        DisclosureGroup {
                            SaveFileRows(file: file)
                        } label: {
                            HStack {
                                Text(file.name).fontWeight(.medium)
                                Spacer()
                                Text(file.slots.isEmpty ? "empty" : "\(file.slots.count) saved game(s)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saves")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        chooseFile(prompt: "Choose an FF7 save file (saveNN.ff7) to add to the game") {
                            viewModel.importDirectly($0)
                        }
                    } label: {
                        Label("Import Save File…", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        chooseFile(prompt: "Choose an FF7 save file (saveNN.ff7) to look at") {
                            viewModel.open($0)
                        }
                    } label: {
                        Label("Open to Look…", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.saveDirectory])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't use that file", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}

/// The saved games inside one save file.
private struct SaveFileRows: View {
    let file: SaveFile
    
    var body: some View {
        if file.slots.isEmpty {
            Text("No saved games in this file.").foregroundStyle(.secondary)
        }
        ForEach(file.slots) { slot in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Slot \(slot.index): \(slot.leader.isEmpty ? "—" : slot.leader)").fontWeight(.medium)
                    Text("Lv \(slot.level)").foregroundStyle(.secondary)
                    Spacer()
                    Text(slot.playTime).monospacedDigit().foregroundStyle(.secondary)
                }
                Text("\(slot.location) · \(slot.gil.formatted()) gil · \(slot.party.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}
