//
//  CVMetaDataStore.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import Foundation

// MARK: - Public model used by UI

struct CVMeta: Identifiable, Hashable {
    var id: UInt16 { number }
    let number: UInt16              // 1-based
    let name: String
    let description: String
    let bitLabels: [Int: String]    // bit 0 is LSB
    let readOnly: Bool
}

// MARK: - JSON DTOs (decoding layer)

private struct CVMetadataFile: Decodable {
    let cvs: [CVMetaDTO]
}

private struct CVMetaDTO: Decodable {
    let number: UInt16
    let name: String
    let description: String
    let bitLabels: [String: String]?
    let readOnly: Bool?

    func toModel() -> CVMeta {
        let converted: [Int: String] = (bitLabels ?? [:]).reduce(into: [:]) { dict, pair in
            if let bit = Int(pair.key) {
                dict[bit] = pair.value
            }
        }

        return CVMeta(
            number: number,
            name: name,
            description: description,
            bitLabels: converted,
            readOnly: readOnly ?? false
        )
    }
}

// MARK: - Store

@MainActor
final class CVMetadataStore: ObservableObject {
    @Published private(set) var byNumber: [UInt16: CVMeta] = [:]
    @Published private(set) var loadError: String? = nil

    /// Call once at app start (or lazily).
    func loadFromBundle(filename: String = "cv_metadata", fileExtension: String = "json") {
        do {
            guard let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) else {
                throw NSError(domain: "CVMetadataStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(filename).\(fileExtension) in bundle"])
            }

            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(CVMetadataFile.self, from: data)

            var dict: [UInt16: CVMeta] = [:]
            for dto in decoded.cvs {
                dict[dto.number] = dto.toModel()
            }

            self.byNumber = dict
            self.loadError = nil
        } catch {
            self.byNumber = [:]
            self.loadError = error.localizedDescription
        }
    }

    func meta(for cv: UInt16) -> CVMeta? {
        byNumber[cv]
    }
}
