//
//  CVExport.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import SwiftUI
import UniformTypeIdentifiers

enum CVExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    var id: String { rawValue }

    var utType: UTType {
        switch self {
            case .csv: return .commaSeparatedText
            case .json: return .json
        }
    }

    var defaultFilename: String {
        switch self {
            case .csv: return "cv_export.csv"
            case .json: return "cv_export.json"
        }
    }
}

// Simple payload for JSON export
struct CVExportJSON: Codable {
    struct Item: Codable {
        let cv: UInt16      // 1-based
        let value: UInt8
        let name: String?
        let description: String?
        let binary: String
    }

    let locomotiveAddress: UInt16
    let exportedAtISO8601: String
    let items: [Item]
}

struct CVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// Helpers
func cvBinaryString(_ v: UInt8) -> String {
    var s = ""
    for bit in (0...7).reversed() {
        s.append(((v >> bit) & 1) == 1 ? "1" : "0")
    }
    return s
}

@MainActor
func makeCSVExport(
    locoAddress: UInt16,
    cvResults: [UInt16: UInt8],
    metaStore: CVMetadataStore
) -> Data {
    // Header row
    var lines: [String] = ["cv,value,binary,name,description"]

    let sorted = cvResults.keys.sorted()
    for cv in sorted {
        let value = cvResults[cv] ?? 0
        let meta = metaStore.meta(for: cv)
        // CSV escaping for quotes/commas/newlines
        func esc(_ s: String?) -> String {
            guard let s else { return "" }
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return s
        }

        let row = [
            "\(cv)",
            "\(value)",
            cvBinaryString(value),
            esc(meta?.name),
            esc(meta?.description)
        ].joined(separator: ",")

        lines.append(row)
    }

    return (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
}

@MainActor
func makeJSONExport(
    locoAddress: UInt16,
    cvResults: [UInt16: UInt8],
    metaStore: CVMetadataStore
) -> Data {
    let sorted = cvResults.keys.sorted()
    let items: [CVExportJSON.Item] = sorted.map { cv in
        let value = cvResults[cv] ?? 0
        let meta = metaStore.meta(for: cv)
        return .init(
            cv: cv,
            value: value,
            name: meta?.name,
            description: meta?.description,
            binary: cvBinaryString(value)
        )
    }

    let payload = CVExportJSON(
        locomotiveAddress: locoAddress,
        exportedAtISO8601: ISO8601DateFormatter().string(from: Date()),
        items: items
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(payload)) ?? Data()
}
