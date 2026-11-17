//
//  NorthernCraterApp.swift
//  NorthernCrater
//

import SwiftUI

@main
struct NorthernCraterApp: App {
    init() {
        try? AppPaths.ensureDirectoriesExist()
    }
    
    var body: some Scene {
        WindowGroup("NorthernCrater") {
            ContentView()
                .frame(minWidth: 860, minHeight: 560)
        }
        .defaultSize(width: 1020, height: 660)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.shared.checkManually() }
                }
            }
        }
    }
}
