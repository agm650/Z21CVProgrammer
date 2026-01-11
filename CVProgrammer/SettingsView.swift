//
//  SettingsView.swift
//  CVProgrammer
//
//  Created by Luc Dandoy on 11/01/2026.
//

import SwiftUI
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case cvRange
        case remote
        case dccEx

        var id: String { rawValue }

        var title: String {
            switch self {
                case .general: return "General"
                case .cvRange: return "CV Range"
                case .remote: return "Remote"
                case .dccEx: return "DCC-EX"
            }
        }

        var systemImage: String {
            switch self {
                case .general: return "gearshape"
                case .cvRange: return "number"
                case .remote: return "antenna.radiowaves.left.and.right"
                case .dccEx: return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationView {
            // Sidebar (macOS 12 style)
            List {
                ForEach(Pane.allCases) { pane in
                    NavigationLink(
                        tag: pane,
                        selection: $selection
                    ) {
                        detailView(for: pane)
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190)

            // Detail placeholder when nothing selected
            Text("Select a section")
                .foregroundStyle(.secondary)
        }
        .frame(width: 760, height: 520)
    }

    @ViewBuilder
    private func detailView(for pane: Pane) -> some View {
        switch pane {
            case .general:
                GeneralSettingsPane()
            case .cvRange:
                CVRangeSettingsPane()
            case .remote:
                RemoteSettingsPane()
            case .dccEx:
                DCCEXSettingsPane()
        }
    }
}

struct GeneralSettingsPane: View {
    @AppStorage(PreferencesKeys.preferredProtocol) private var preferredProtocolRaw: String = CommandStationType.z21.rawValue
    @AppStorage(PreferencesKeys.logAutoScroll) private var logAutoScroll: Bool = true

    private var preferredProtocol: Binding<CommandStationType> {
        Binding(
            get: { CommandStationType(rawValue: preferredProtocolRaw) ?? .z21 },
            set: { preferredProtocolRaw = $0.rawValue }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("General")
                    .font(.title2)
                    .bold()

                GroupBox("Defaults") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Default protocol", selection: preferredProtocol) {
                            ForEach(CommandStationType.allCases) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .frame(width: 260)

                        Toggle("Auto-scroll log", isOn: $logAutoScroll)
                    }
                    .padding(.top, 6)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }
}

struct CVRangeSettingsPane: View {
    @AppStorage(PreferencesKeys.maxCvValue) private var maxCvValue: Int = 255

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("CV Range")
                    .font(.title2)
                    .bold()

                GroupBox("Limits") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Text("Maximum CV value")
                                .frame(width: 180, alignment: .leading)

                            Spacer()

                            TextField("", text: $text)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                                .focused($focused)
                                .onSubmit { commit() }

                            Stepper("", value: $maxCvValue, in: 1...255, step: 1)
                                .labelsHidden()
                                .onChange(of: maxCvValue) { v in text = "\(v)" }
                        }

                        Text("Upper bound used by the CV field and range reads (CV 1…Max).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 6)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .onAppear { text = "\(maxCvValue)" }
        .onChange(of: focused) { isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(trimmed) else { text = "\(maxCvValue)"; return }
        let clamped = Swift.max(1, Swift.min(255, v))
        maxCvValue = clamped
        text = "\(clamped)"
    }
}

struct RemoteSettingsPane: View {
    @AppStorage(PreferencesKeys.remoteIP) private var host: String = "192.168.0.111"
    @AppStorage(PreferencesKeys.remotePort) private var port: Int = 21105

    @State private var portText: String = ""
    @FocusState private var portFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Remote Host")
                    .font(.title2)
                    .bold()

                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Host")
                                .frame(width: 180, alignment: .leading)
                            TextField("", text: $host)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 12) {
                            Text("Port")
                                .frame(width: 180, alignment: .leading)

                            TextField("", text: $portText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .focused($portFocused)
                                .onSubmit { commitPort() }

                            Stepper("", value: $port, in: 1...65535, step: 1)
                                .labelsHidden()
                                .onChange(of: port) { v in portText = "\(v)" }

                            Spacer()
                        }

                        Text("Default connection used when you choose z21 in the main window.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .onAppear { portText = "\(port)" }
        .onChange(of: portFocused) { focused in
            if !focused { commitPort() }
        }
    }

    private func commitPort() {
        let trimmed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(trimmed) else { portText = "\(port)"; return }
        let clamped = Swift.max(1, Swift.min(65535, v))
        port = clamped
        portText = "\(clamped)"
    }
}

struct DCCEXSettingsPane: View {
    @AppStorage(PreferencesKeys.timeOut) private var timeoutMs: Int = 3000

    @State private var timeoutText: String = ""

    @FocusState private var portFocused: Bool
    @FocusState private var timeoutFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("DCC-EX")
                    .font(.title2)
                    .bold()

                GroupBox("Programming") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Timeout")
                                .frame(width: 180, alignment: .leading)

                            TextField("", text: $timeoutText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                                .multilineTextAlignment(.trailing)
                                .focused($timeoutFocused)
                                .onSubmit { commitTimeout() }

                            Text("ms")
                                .foregroundStyle(.secondary)

                            Stepper("", value: $timeoutMs, in: 250...20000, step: 250)
                                .labelsHidden()
                                .onChange(of: timeoutMs) { v in timeoutText = "\(v)" }

                            Spacer()
                        }

                        Text("Time to wait for a programming track response before declaring failure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .onAppear {
            timeoutText = "\(timeoutMs)"
        }
        .onChange(of: timeoutFocused) { focused in
            if !focused { commitTimeout() }
        }
    }

    private func commitTimeout() {
        let trimmed = timeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v = Int(trimmed) else { timeoutText = "\(timeoutMs)"; return }
        let clamped = Swift.max(250, Swift.min(20000, v))
        timeoutMs = clamped
        timeoutText = "\(clamped)"
    }
}

