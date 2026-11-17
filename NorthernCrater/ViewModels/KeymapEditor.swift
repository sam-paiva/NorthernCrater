//
//  KeymapEditor.swift
//  NorthernCrater
//
//  The state of the keyboard page: the layout, and "press a key" capture for one button at a time. Every
//  change is saved to keymap.txt at once; the engine reads it when the game starts.
//

import AppKit
import Observation

@MainActor
@Observable
final class KeymapEditor {
    private(set) var bindings: KeyBindings
    /// The button waiting for a key press, if any.
    private(set) var capturing: String?
    private(set) var note: String?
    @ObservationIgnored private var monitor: Any?

    init() {
        bindings = KeymapStore.load()
    }

    var isDefault: Bool { bindings == .defaults }

    func beginCapture(_ button: String) {
        endCapture()
        capturing = button
        note = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    func endCapture() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturing = nil
    }

    func remove(key: Int, from button: String) {
        bindings.keys[button]?.removeAll { $0 == key }
        note = nil
        save()
    }

    func resetToDefaults() {
        endCapture()
        bindings = .defaults
        note = "Back to the default layout."
        save()
    }

    // MARK: - Capture

    /// The modifier keys the engine can press a button with (it reads their state changes).
    private static let modifierFlags: [Int: NSEvent.ModifierFlags] = [
        56: .shift, 60: .shift, 59: .control, 62: .control, 58: .option, 61: .option, 57: .capsLock,
    ]

    /// Returns nil to swallow the event, so the key does not also trigger the page's own controls.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let code = Int(event.keyCode)
        if event.type == .flagsChanged {
            // Command and Fn cannot be used; the others count when pressed (not when released).
            if let flag = Self.modifierFlags[code], event.modifierFlags.contains(flag) { assign(code) }
            return nil
        }
        guard !event.isARepeat else { return nil }
        if code == 53 { endCapture(); note = "Cancelled."; return nil }                 // Esc leaves capture
        if event.modifierFlags.contains(.command) { note = "Command shortcuts cannot be used as game keys."; return nil }
        if code == 122 { note = "F1 opens the achievements panel in the game, so it cannot be used."; return nil }
        guard (0..<128).contains(code) else { note = "That key cannot be used."; return nil }
        assign(code)
        return nil
    }

    private func assign(_ code: Int) {
        guard let button = capturing else { return }
        var moved: String?
        if let other = bindings.button(for: code), other != button {
            bindings.keys[other]?.removeAll { $0 == code }
            moved = KeyBindings.buttons.first { $0.id == other }?.title
        }
        if bindings.keys(for: button).contains(code) == false { bindings.keys[button, default: []].append(code) }
        note = moved.map { "\(KeyNames.name(code)) was used for \"\($0)\" and moved here." }
        endCapture()
        save()
    }

    private func save() {
        do { try KeymapStore.save(bindings) } catch { note = "Could not save the layout: \(error.localizedDescription)" }
    }
}
