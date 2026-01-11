//
//  CVProgrammerApp.swift
//  CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//
// https://docs.tcsdcc.com/wiki/

import SwiftUI

@main
struct CVProgrammerApp: App {
    @StateObject private var metaStore = CVMetadataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(metaStore)
                .onAppear {
                    metaStore.loadFromBundle()
                }
        }
        .windowStyle(.titleBar)
        Settings {
            SettingsView()
        }
    }
}
