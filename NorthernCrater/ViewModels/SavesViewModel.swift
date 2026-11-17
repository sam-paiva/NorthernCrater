//
//  SavesViewModel.swift
//  NorthernCrater
//

import Foundation
import Observation

@Observable
@MainActor
final class SavesViewModel {
    var gameSaves: [SaveFile] = []
    var openedFile: SaveFile?          // a file read from anywhere, for a look before importing
    var message: String?
    var errorMessage: String?
    
    @ObservationIgnored private let service: any SaveManaging
    
    init(service: any SaveManaging = SaveService()) {
        self.service = service
        refresh()
    }
    
    func refresh() {
        gameSaves = service.gameSaves()
    }
    
    /// Reads a file the user picked. Files outside the app's folders need their security scope
    /// started first (a no-op when the app is not sandboxed).
    func open(_ url: URL) {
        errorMessage = nil
        message = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            openedFile = try service.read(url)
        } catch {
            openedFile = nil
            errorMessage = error.localizedDescription
        }
    }
    
    /// One step: read the chosen file and copy it into the game's first free save file.
    func importDirectly(_ url: URL) {
        errorMessage = nil
        message = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try service.importSave(url)
            message = "Imported \(url.lastPathComponent) as \(imported.name) in \(AppPaths.saveDirectory.path)."
            openedFile = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func importOpenedFile() {
        guard let file = openedFile else { return }
        errorMessage = nil
        let scoped = file.url.startAccessingSecurityScopedResource()
        defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try service.importSave(file.url)
            message = "Imported \(file.name) as \(imported.name)."
            openedFile = nil
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func closeOpenedFile() {
        openedFile = nil
        message = nil
        errorMessage = nil
    }
}
