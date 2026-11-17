//
//  ControlsView.swift
//  NorthernCrater
//
//  The keyboard and controller page: a keyboard layout editor (written to keymap.txt, which the engine reads
//  at start-up) and a controller page with a live button tester and the analog options (FFNx.toml).
//

import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: ModManagerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var editor = KeymapEditor()
    @State private var monitor = ControllerMonitor()

    init(viewModel: ModManagerViewModel, initialTab: Tab = .keyboard) {
        self.viewModel = viewModel
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case keyboard = "Keyboard", controller = "Controller"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])
            .frame(maxWidth: 360)

            switch tab {
            case .keyboard: KeyboardPane(editor: editor)
            case .controller: ControllerPane(monitor: monitor, config: $viewModel.launchConfig)
            }

            HStack {
                Text("Applied the next time you start the game.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 640)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop(); editor.endCapture() }
    }
}

// MARK: - Keyboard

private struct KeyboardPane: View {
    var editor: KeymapEditor

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(KeyBindings.buttons) { button in
                        row(button)
                    }
                } footer: {
                    Text("Press a game button's + and then the key you want. A key can only do one thing: using it again moves it. Esc cancels. Command shortcuts and F1 (achievements) are reserved. The game's own Config menu decides what each pad button does.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let note = editor.note { Text(note).font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button("Reset to defaults") { editor.resetToDefaults() }
                    .disabled(editor.isDefault)
            }
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    private func row(_ button: GameButton) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(button.title)
                Text("pad \(button.padButton)").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)
            FlowRow {
                ForEach(editor.bindings.keys(for: button.id), id: \.self) { key in
                    KeyChip(name: KeyNames.name(key)) { editor.remove(key: key, from: button.id) }
                }
                if editor.capturing == button.id {
                    Text("Press a key…")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.25), in: Capsule())
                } else {
                    Button { editor.beginCapture(button.id) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("Add a key for \(button.title)")
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct KeyChip: View {
    let name: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(name).font(.caption.monospaced())
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove \(name)")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

/// Left-to-right layout that wraps onto the next line.
private struct FlowRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        WrapLayout(spacing: 6) { content }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}

// MARK: - Controller

private struct ControllerPane: View {
    var monitor: ControllerMonitor
    @Binding var config: GameLaunchConfig

    var body: some View {
        Form {
            Section("Connected controllers") {
                if monitor.controllerNames.isEmpty {
                    Text("No controller found. Connect one with USB or Bluetooth, then press a button on it.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.controllerNames, id: \.self) { Label($0, systemImage: "gamecontroller") }
                    Text("The game uses the first one.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !monitor.controllerNames.isEmpty {
                Section("Test your buttons") {
                    tester
                }
            }
            Section("Buttons") {
                Toggle("Swap confirm and cancel", isOn: $config.swapConfirmCancel)
                Text("Exchanges the controller's A and B buttons (the bottom and the right face button), so the one that cancels confirms and the other way round. The keyboard is not affected.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Analog sticks") {
                Toggle("Analog movement (walk in any direction)", isOn: $config.analogControls)
                Toggle("Walk or run by how far the stick is tilted", isOn: $config.autoRun)
                deadzone("Left stick dead zone", value: $config.leftStickDeadzone)
                deadzone("Right stick dead zone", value: $config.rightStickDeadzone)
            }
            Section("Battle camera") {
                Toggle("Invert vertical", isOn: $config.invertCameraVertical)
                Toggle("Invert horizontal", isOn: $config.invertCameraHorizontal)
            }
            Section {
                EmptyView()
            } footer: {
                Text("Each controller button presses a game button (shown in the test). To change what a game button does beyond the swap above, use the game's own Config menu, Controller. The dead zone is how far a stick must move before the game notices it: raise it if your character drifts.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    /// What the engine presses for this button, with the confirm/cancel swap applied.
    private func gamePad(of item: (id: String, label: String, gamePad: String)) -> String {
        guard config.swapConfirmCancel else { return item.gamePad }
        switch item.id {
        case "a": return "B (OK)"
        case "b": return "A (cancel)"
        default: return item.gamePad
        }
    }

    private func deadzone(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Slider(value: value, in: 0...0.5, step: 0.05)
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 36)
        }
    }

    private var tester: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrapLayout(spacing: 6) {
                ForEach(ControllerMonitor.layout, id: \.id) { item in
                    let on = monitor.pressed.contains(item.id)
                    VStack(spacing: 1) {
                        Text(item.label).font(.caption2)
                        Text("→ " + gamePad(of: item)).font(.caption2.bold())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(on ? Color.white : Color.primary)
                }
            }
            HStack(spacing: 24) {
                StickView(title: "Left stick", point: monitor.leftStick, deadzone: config.leftStickDeadzone)
                StickView(title: "Right stick", point: monitor.rightStick, deadzone: config.rightStickDeadzone)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Triggers").font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: Double(monitor.leftTrigger)).frame(width: 90)
                    ProgressView(value: Double(monitor.rightTrigger)).frame(width: 90)
                }
            }
        }
    }
}

/// A stick's position inside its circle; the inner circle is the dead zone (movement inside it is ignored).
private struct StickView: View {
    let title: String
    let point: CGPoint
    let deadzone: Double
    private let size: CGFloat = 70

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.5))
                Circle().fill(.secondary.opacity(0.12)).frame(width: size * deadzone * 2, height: size * deadzone * 2)
                Circle().fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .offset(x: point.x * (size / 2 - 5), y: -point.y * (size / 2 - 5))
            }
            .frame(width: size, height: size)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
