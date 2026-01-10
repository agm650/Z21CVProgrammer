//
//  ContentView.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import SwiftUI

enum CommandStationType: String, CaseIterable, Identifiable {
    case z21 = "Roco z21"
    case dccEx = "DCC-EX"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var meta: CVMetadataStore
    @StateObject var z21 = Z21Client()
    @StateObject var dcc = DCCEXBackend()
    @State private var type: CommandStationType = .z21

    @State private var host: String = "192.168.0.111"
    @State private var port: UInt16 = 21105

    @State private var locoAddress: UInt16 = 3
    @State private var cvNumber1Based: UInt16 = 1
    @State private var cvValue: UInt8 = 3
    @State private var maxCvValue: UInt8 = 106

    // CV results stored by CV number (1-based for display)
    @State private var cvResults: [UInt16: UInt8] = [:]

    // Range read task
    @State private var rangeTask: Task<Void, Never>?

    // Load CV value
    @State private var selectedCV: UInt16? = nil

    // Metadata
    @EnvironmentObject private var metaStore: CVMetadataStore

    // export support
    @State private var isExporting = false
    @State private var exportFormat: CVExportFormat = .csv
    @State private var exportDocument = CVExportDocument(data: Data())
    @State private var exportFilename = "cv_export.csv"

    private var client: any CVBackend { type == .z21 ? z21 : dcc }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("CV Programming Tool")
                    .font(.title2)
                    .bold()
                Picker("Protocol", selection: $type) {
                    ForEach(CommandStationType.allCases) { Text($0.rawValue).tag($0) }
                }
                GroupBox("Connection") {
                    HStack {
                        TextField("IP / Host", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)

                        TextField("Port", value: $port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Button(client.isRunning ? "Disconnect" : "Connect") {
                            if client.isRunning {
                                client.disconnect()
                            } else {
                                client.connect(host: host, port: port)
                            }
                        }
                    }

                    HStack {
                        Circle()
                            .fill(client.isRunning ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(client.isRunning ? "Ready" : "Not connected")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("POM (Programming on the Main)") {
                    VStack(alignment: .leading, spacing: 10) {

                        metadataErrorView

                        Text("Note: POM read needs RailCom enabled in the Z21 and in the decoder.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Locomotive Address")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $locoAddress, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .disabled(type == .dccEx)
                            }

                            VStack(alignment: .leading) {
                                Text("CV (1–\(maxCvValue))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $cvNumber1Based, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .onChange(of: cvNumber1Based) {
                                        v in
                                        if v < 1 { cvNumber1Based = 1 }
                                        if v > maxCvValue { cvNumber1Based = UInt16(maxCvValue) }
                                    }
                                    .onChange(of: cvValue) { v in
                                        // UInt8 is already 0..255, so no clamp needed unless you use Int input.
                                    }
                            }

                            VStack(alignment: .leading) {
                                Text("Value (0–255)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $cvValue, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .disabled(isCurrentReadOnly)
                            }

                            Spacer()

                            Button("Write CV") { client.writeCV(locoAddress: type == .z21 ? locoAddress : nil, cv: cvNumber1Based, value: cvValue) }
                                .disabled(!client.isRunning || isCurrentReadOnly)

                            Button("Read CV") {
                                // readCV(single: cvNumber1Based)
                                client.readCV(
                                    locoAddress: type == .z21 ? locoAddress : nil, cv: cvNumber1Based)
                            }.disabled(!client.isRunning)
                        }

                        if let meta = currentMeta {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CV\(meta.number): \(meta.name)")
                                    .font(.headline)
                                Text(meta.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                if isCurrentReadOnly {
                                    Text("This CV is marked read-only and cannot be written.")
                                        .font(.footnote).foregroundColor(.red)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 6)
                        }
                        BitEditorView(
                            value: $cvValue,
                            bitLabels: currentMeta?.bitLabels ?? [:]
                        )
                        .disabled(isCurrentReadOnly)
                        .opacity(isCurrentReadOnly ? 0.6 : 1.0)
                        .padding(.top, 8)
                        Divider()

                        HStack {
                            Button("Read CV 1–\(maxCvValue)") {
                                startReadRange()
                            }
                            .disabled(!client.isRunning || rangeTask != nil)

                            Button("Stop") {
                                rangeTask?.cancel()
                                rangeTask = nil
                            }
                            .disabled(rangeTask == nil)

                            Button("Clear Results") {
                                cvResults.removeAll()
                            }

                            Picker("Export", selection: $exportFormat) {
                                ForEach(CVExportFormat.allCases) { f in
                                    Text(f.rawValue).tag(f)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)

                            Button("Export…") {
                                prepareExport()
                            }
                            .disabled(cvResults.isEmpty)

                            Spacer()

                            Text("Read: \(cvResults.count)/\(maxCvValue)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox("CV Results") {
                    Table(rows, selection: $selectedCV) {
                        TableColumn("CV") { row in
                            Text("\(row.cv)").monospacedDigit()
                        }
                        TableColumn("Value") { row in
                            Text("\(row.value)").monospacedDigit()
                        }
                    }
                    .onChange(of: selectedCV) { newValue in
                        guard let cv = newValue else { return }
                        cvNumber1Based = cv
                        if let v = cvResults[cv] {
                            cvValue = v
                        }
                    }
                    .frame(minHeight: 220, maxHeight: 220)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Log")
                                .font(.headline)

                            Spacer()

                            Button("Clear Log") {
                                client.clearLog()
                            }
                            .disabled(client.logText.isEmpty)
                        }

                        Divider()

                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(client.logText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(.vertical, 4)

                                // Anchor at bottom for scrolling
                                Color.clear
                                    .frame(height: 1)
                                    .id("LOG_BOTTOM")
                            }
                            .frame(minHeight: 160)
                            .onChange(of: client.logText) { _ in
                                // Auto-scroll to bottom whenever new log arrives
                                withAnimation(nil) {
                                    proxy.scrollTo("LOG_BOTTOM", anchor: .bottom)
                                }
                            }
                            .onAppear {
                                // Ensure it starts scrolled to bottom
                                proxy.scrollTo("LOG_BOTTOM", anchor: .bottom)
                            }
                        }
                    }
                } // no "Log" title here because we made our own header row


                Spacer()
            }
            .padding(16)
            .frame(minWidth: 820, minHeight: 620)
//            .onReceive(client.events) { event in
//                switch event {
//                    case .cvResult(let cv0, let value):
//                        let cv1 = cv0 &+ 1
//                        if (1...UInt16(maxCvValue)).contains(cv1) {
//                            cvResults[cv1] = value
//                        }
//                        // If the user is currently viewing this CV, update the editor + bit view
//                        if cv1 == cvNumber1Based {
//                            cvValue = value
//                        }
//                    case .cvNack:
//                        break
//                    case .unknown:
//                        break
//                }
//            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: exportFormat.utType,
                defaultFilename: exportFilename
            ) { result in
                // Optional: log success/failure
                switch result {
                    case .success(let url):
                        client.appendExternalLog("Exported to \(url.lastPathComponent)")
                    case .failure(let error):
                        client.appendExternalLog("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private var rows: [CVRow] {
        cvResults
            .map { CVRow(cv: $0.key, value: Int($0.value)) }
            .sorted { $0.cv < $1.cv }
    }

    private func startReadRange() {
        rangeTask?.cancel()

        rangeTask = Task {
            for cv in 1...maxCvValue {
                if Task.isCancelled { break }
                // client.readCV(locoAddress: type == .z21 ? locoAddress : nil, cv: cvNumber1Based)
                client.readCV(locoAddress: type == .z21 ? locoAddress : nil, cv: UInt16(cv))

                // Small pacing to avoid flooding the command station.
                // Tweak as needed depending on your z21/decoder responsiveness.
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
            }

            await MainActor.run { rangeTask = nil }
        }
    }

    private var currentMeta: CVMeta? {
       return   metaStore.meta(for: cvNumber1Based)
    }

    @ViewBuilder
    private var metadataErrorView: some View {
        if let err = metaStore.loadError {
            Text("Metadata load error: \(err)")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func prepareExport() {
        let data: Data
        switch exportFormat {
            case .csv:
                data = makeCSVExport(
                    locoAddress: locoAddress,
                    cvResults: cvResults,
                    metaStore: metaStore
                )
                exportFilename = exportFormat.defaultFilename

            case .json:
                data = makeJSONExport(
                    locoAddress: locoAddress,
                    cvResults: cvResults,
                    metaStore: metaStore
                )
                exportFilename = exportFormat.defaultFilename
        }

        exportDocument = CVExportDocument(data: data)
        isExporting = true
    }

    private func appendUILog(_ line: String) {
        // piggyback on the existing client.logText without changing client
        client.appendExternalLog(line)
    }

    private var isCurrentReadOnly: Bool {
        currentMeta?.readOnly == true
    }
}

struct CVRow: Identifiable {
    var id: UInt16 { cv }
    let cv: UInt16
    let value: Int
}
