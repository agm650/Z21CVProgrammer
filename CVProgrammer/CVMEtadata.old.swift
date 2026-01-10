//
//  CVMEtadata.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import Foundation

struct CVMeta: Identifiable, Hashable {
    var id: UInt16 { number }
    let number: UInt16            // 1-based
    let name: String
    let description: String
    /// Optional per-bit labels (bit 0 is LSB). Only provide if you actually know them.
    let bitLabels: [Int: String]
}

enum CVCatalog {
    /// Minimal starter set you asked for. Expand freely.
    static let items: [UInt16: CVMeta] = [
        1: CVMeta(
            number: 1,
            name: "Address",
            description: "Primary (short) locomotive address (typically 1–127).",
            bitLabels: [:]
        ),
        2: CVMeta(
            number: 2,
            name: "Initial Speed",
            description: "Start voltage / Vstart (kick-start speed).",
            bitLabels: [:]
        ),
        29: CVMeta(
            number: 29,
            name: "Configuration Register",
            description: "Bit field controlling core decoder behavior (direction, speed steps, addressing, etc.).",
            // Leave labels empty unless you want to encode exact meaning per decoder/standard.
            bitLabels: [
                // Example labels only; you may want to adjust/remove.
                0: "Direction",
                1: "28/128 speed steps",
                2: "Analog operation",
                3: "RailCom / Comms (varies)",
                4: "Speed table selection",
                5: "Long address enable",
                6: "Reserved",
                7: "Reserved"
            ]
        )
    ]

    static func meta(for cv: UInt16) -> CVMeta? {
        items[cv]
    }
}
