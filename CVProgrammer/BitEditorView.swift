//
//  BitEditorView.swift
//  CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//

import SwiftUI

/// Edits an UInt8 as 8 clickable bits. Bit 0 is LSB (value 1).
struct BitEditorView: View {
    @Binding var value: UInt8
    var bitLabels: [Int: String] = [:]   // bit -> label
    var showBinaryString: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showBinaryString {
                Text("Binary: \(binaryString(value))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Display bits MSB -> LSB for readability (7 ... 0)
            HStack(spacing: 10) {
                ForEach((0...7).reversed(), id: \.self) { bit in
                    BitButton(
                        bit: bit,
                        isOn: isBitSet(value, bit: bit),
                        label: bitLabels[bit]
                    ) {
                        toggleBit(bit)
                    }
                }
            }
        }
    }

    private func toggleBit(_ bit: Int) {
        let mask = UInt8(1 << bit)
        value ^= mask
    }

    private func isBitSet(_ v: UInt8, bit: Int) -> Bool {
        (v & UInt8(1 << bit)) != 0
    }

    private func binaryString(_ v: UInt8) -> String {
        var s = ""
        for bit in (0...7).reversed() {
            s.append(((v >> bit) & 1) == 1 ? "1" : "0")
        }
        return s
    }
}

private struct BitButton: View {
    let bit: Int
    let isOn: Bool
    let label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("b\(bit)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(isOn ? "1" : "0")
                    .font(.system(.headline, design: .monospaced))
                    .frame(width: 30, height: 30)
                    .background(isOn ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if let label, !label.isEmpty {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 64)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(label ?? "Toggle bit \(bit)")
    }
}
