//
//  ModDetailView.swift
//  NorthernCrater
//
//  A mod's page, laid out like 7th Heaven's Configure window: the options in a list on the left (a mod's
//  headings, such as "===World Screen===", become collapsible groups), and for the selected option on the
//  right its description, its choices, a large picture of the chosen choice and, where the mod ships one,
//  a button to hear it.
//

import SwiftUI

extension ModOption {
    /// A heading some mods put in their option list ("===World Screen===": one choice, no name).
    var isSectionHeader: Bool { choices.count == 1 && (choices.first?.name.isEmpty ?? true) }

    /// A plain on/off option (a Bool in mod.xml).
    var isOnOff: Bool { choices.map(\.id) == ["0", "1"] && choices.map(\.name) == ["Off", "On"] }
}

/// A mod's preview picture, loaded in the background when it first appears.
struct ModPreviewImage: View {
    let modURL: URL
    let path: String?
    var maxHeight: CGFloat = 200
    @State private var image: NSImage?

    var body: some View {
        // The task hangs on a view that always exists: on an empty view (no picture yet) SwiftUI never runs it.
        ZStack {
            Color.clear.frame(height: 1)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: path) {
            image = nil
            guard let path, !path.isEmpty,
                  let loaded = await ModPreviewStore.shared.image(modURL: modURL, path: path) else { return }
            image = NSImage(cgImage: loaded.cgImage, size: .zero)
        }
    }
}

struct ModDetailView: View {
    @Binding var mod: ModItem
    /// The option the page opens on (-1 = the mod's own page).
    var initialSelection = -1
    /// Index into `mod.options` of the option shown on the right; -1 = the mod's own page.
    @State private var selection = -1
    @State private var expanded: Set<Int> = []

    /// The options in order, split at the mod's headings. `header` is the heading's option index.
    private struct OptionGroup: Identifiable {
        let header: Int?
        var members: [Int]
        var id: Int { header ?? -1 }
    }

    private var groups: [OptionGroup] {
        var result: [OptionGroup] = []
        for index in mod.options.indices {
            if mod.options[index].isSectionHeader {
                result.append(OptionGroup(header: index, members: []))
            } else if result.isEmpty {
                result.append(OptionGroup(header: nil, members: [index]))
            } else {
                result[result.count - 1].members.append(index)
            }
        }
        return result
    }

    /// Small mods open fully; a big one (Symphonic Remasters has 99) opens its first group.
    private func resetView() {
        selection = initialSelection
        let all = groups.compactMap(\.header)
        expanded = Set(mod.options.count <= 40 ? all : Array(all.prefix(1)))
    }

    var body: some View {
        HSplitView {
            optionList
                .frame(minWidth: 240, idealWidth: 290, maxWidth: 420)
            detailPane
                .frame(minWidth: 340, maxWidth: .infinity)
        }
        .navigationTitle(mod.name)
        .onAppear(perform: resetView)
        .onChange(of: mod.id) { resetView() }
        .onDisappear { ModAudioPreview.shared.stop() }
    }

    // MARK: - Left: the option list

    private var optionList: some View {
        List(selection: $selection) {
            Label("About this mod", systemImage: "info.circle")
                .tag(-1)
            ForEach(groups) { group in
                if let header = group.header {
                    DisclosureGroup(isExpanded: expansion(of: header)) {
                        rows(group.members)
                    } label: {
                        Text(title(ofHeader: header)).font(.headline)
                    }
                } else {
                    rows(group.members)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ members: [Int]) -> some View {
        ForEach(members, id: \.self) { index in
            optionRow(index).tag(index)
        }
    }

    private func optionRow(_ index: Int) -> some View {
        let option = mod.options[index]
        return HStack {
            Text(option.name).lineLimit(1)
            Spacer(minLength: 8)
            Text(option.selectedChoice?.name ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func title(ofHeader index: Int) -> String {
        let text = mod.options[index].name.trimmingCharacters(in: CharacterSet(charactersIn: "= "))
        return text.isEmpty ? "Options" : text
    }

    private func expansion(of header: Int) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(header) },
            set: { open in
                if open { expanded.insert(header) } else { expanded.remove(header) }
            }
        )
    }

    // MARK: - Right: the selected option

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if mod.options.indices.contains(selection) {
                    optionPane(selection)
                } else {
                    aboutPane
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModPreviewImage(modURL: mod.archiveURL, path: mod.previewFile, maxHeight: 400)
            Text(mod.name).font(.title2.bold())
            VStack(spacing: 0) {
                infoRow("Author", mod.author)
                Divider()
                infoRow("Version", mod.version)
                Divider()
                infoRow("Category", mod.category)
                Divider()
                infoRow("Archive", mod.archiveURL.lastPathComponent)
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            if mod.options.isEmpty {
                Text("This mod has no options to configure.").foregroundStyle(.secondary)
            } else {
                Text("Pick an option on the left to see what each choice looks like.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }

    private func optionPane(_ index: Int) -> some View {
        let option = mod.options[index]
        let choice = option.selectedChoice
        return VStack(alignment: .leading, spacing: 14) {
            Text(option.name).font(.title2.bold())
            let note = option.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty {
                Text(note)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            choiceControl(index)
            ModPreviewImage(modURL: mod.archiveURL, path: choice?.previewFile, maxHeight: 440)
            if let audio = choice?.previewAudio, !audio.isEmpty {
                SoundPreviewButton(modURL: mod.archiveURL, path: audio)
            }
        }
    }

    @ViewBuilder
    private func choiceControl(_ index: Int) -> some View {
        let option = mod.options[index]
        if option.isOnOff {
            Toggle(option.name, isOn: Binding(
                get: { mod.options[index].selectedChoiceId == "1" },
                set: { mod.options[index].selectedChoiceId = $0 ? "1" : "0" }
            ))
        } else {
            Picker("Choice", selection: $mod.options[index].selectedChoiceId) {
                ForEach(option.choices) { choice in
                    Text(choice.name.isEmpty ? "Default" : choice.name).tag(choice.id)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

/// Plays or stops a mod's sound preview for one choice.
struct SoundPreviewButton: View {
    let modURL: URL
    let path: String
    private var audio: ModAudioPreview { ModAudioPreview.shared }

    var body: some View {
        let key = ModAudioPreview.key(modURL: modURL, path: path)
        VStack(alignment: .leading, spacing: 6) {
            Button {
                audio.toggle(modURL: modURL, path: path)
            } label: {
                if audio.preparingKey == key {
                    Label("Preparing sound…", systemImage: "hourglass")
                } else if audio.playingKey == key {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Play sound preview", systemImage: "play.fill")
                }
            }
            if let message = audio.errorMessage, audio.preparingKey == nil, audio.playingKey == nil {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
