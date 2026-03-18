//
//  codexswitchApp.swift
//  codexswitch
//
//  Created by 陈浩亮 on 2026/3/18.
//

import SwiftUI

@main
struct codexswitchApp: App {
    @StateObject private var store = CodexAccountsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Label("Codex", systemImage: store.statusIconName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
