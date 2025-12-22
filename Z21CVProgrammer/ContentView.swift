//
//  ContentView.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var client = Z21Client()

    @State private var host: String = "192.168.0.111"
    @State private var port: UInt16 = 21105

    @State private var locoAddress: UInt16 = 3
    @State private var cvNumber1Based: UInt16 = 1
    @State private var cvValue: UInt8 = 3

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


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("z21 POM CV Tool")
                    .font(.title2)
                    .bold()

                GroupBox("Connection") {
                    HStack {
                        TextField("z21 IP / Host", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 220)

                        TextField("Port", value: $port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)

                        Button(client.isRunning ? "Disconnect" : "Connect") {
                            if client.isRunning {
                                client.stop()
                            } else {
                                client.start(host: host, port: port)
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
                            }

                            VStack(alignment: .leading) {
                                Text("CV (1–255)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("", value: $cvNumber1Based, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .onChange(of: cvNumber1Based) {
                                        v in
                                        if v < 1 { cvNumber1Based = 1 }
                                        if v > 255 { cvNumber1Based = 255 }
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
                            }

                            Spacer()

                            Button("Write CV") { writeCV() }
                                .disabled(!client.isRunning)

                            Button("Read CV") { readCV(single: cvNumber1Based) }
                                .disabled(!client.isRunning)
                        }

                        if let meta = currentMeta {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("CV\(meta.number): \(meta.name)")
                                    .font(.headline)
                                Text(meta.description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                        BitEditorView(
                            value: $cvValue,
                            bitLabels: currentMeta?.bitLabels ?? [:]
                        )
                        .padding(.top, 8)
                        Divider()

                        HStack {
                            Button("Read CV 1–255") {
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

                            Text("Read: \(cvResults.count)/255")
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
                    .frame(minHeight: 220)
                }

                GroupBox("Log") {
                    ScrollView {
                        Text(client.logText)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                    }
                    .frame(minHeight: 160)
                }

                Spacer()
            }
            .padding(16)
            .frame(minWidth: 820, minHeight: 620)
            .onReceive(client.events) { event in
                switch event {
                    case .cvResult(let cv0, let value):
                        let cv1 = cv0 &+ 1
                        // Only store 1..255 as requested
                        if (1...255).contains(cv1) {
                            cvResults[cv1] = value
                        }
                        // ✅ If the user is currently viewing this CV, update the editor + bit view
                        if cv1 == cvNumber1Based {
                            cvValue = value
                        }
                    case .cvNack:
                        break
                    case .unknown:
                        break
                }
            }
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

    private func writeCV() {
        guard (1...255).contains(cvNumber1Based) else { return }
        let cv0 = cvNumber1Based - 1

        let packet = Z21Protocol.makePOMWriteBytePacket(
            locoAddress: locoAddress,
            cvAddress0Based: cv0,
            value: cvValue
        )
        client.send(packet, note: "POM WRITE: addr=\(locoAddress) cv=\(cvNumber1Based) val=\(cvValue)")
    }

    private func readCV(single cv1Based: UInt16) {
        guard (1...255).contains(cv1Based) else { return }
        let cv0 = cv1Based - 1

        let packet = Z21Protocol.makePOMReadBytePacket(
            locoAddress: locoAddress,
            cvAddress0Based: cv0
        )
        client.send(packet, note: "POM READ: addr=\(locoAddress) cv=\(cv1Based)")
    }

    private func startReadRange() {
        rangeTask?.cancel()

        rangeTask = Task {
            for cv in 1...255 {
                if Task.isCancelled { break }
                readCV(single: UInt16(cv))

                // Small pacing to avoid flooding the command station.
                // Tweak as needed depending on your z21/decoder responsiveness.
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
            }

            await MainActor.run { rangeTask = nil }
        }
    }

    private var currentMeta: CVMeta? {
        let cvstore = metaStore.meta(for: cvNumber1Based)

        if let err = metaStore.loadError {
            Text("Metadata load error: \(err)")
                .font(.footnote)
                .foregroundStyle(.red)
        }

        return cvstore
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

}

struct CVRow: Identifiable {
    var id: UInt16 { cv }
    let cv: UInt16
    let value: Int
}
