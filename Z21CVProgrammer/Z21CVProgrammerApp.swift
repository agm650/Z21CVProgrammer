//
//  Z21CVProgrammerApp.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import SwiftUI

@main
struct Z21CVProgrammerApp: App {
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
    }
}
