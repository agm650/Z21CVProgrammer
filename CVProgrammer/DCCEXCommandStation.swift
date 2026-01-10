//
//  DCCEXCommandStation.swift
//  CVProgrammer
//
//  Created by Luc Dandoy on 10/01/2026.
//

import Foundation
import Network
import Combine

@MainActor
final class DCCEXCommandStation: ObservableObject, CommandStation {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var logText: String = ""

    private let eventsSubject = PassthroughSubject<CVEvent, Never>()
    var events: AnyPublisher<CVEvent, Never> { eventsSubject.eraseToAnyPublisher() }

    private var connection: NWConnection?

    // Buffer for TCP stream parsing
    private var rxBuffer = Data()

    func connect(host: String, port: UInt16) {
        disconnect()

        let h = NWEndpoint.Host(host)
        guard let p = NWEndpoint.Port(rawValue: port) else {
            appendLog("Invalid port: \(port)")
            eventsSubject.send(.failure("Invalid port"))
            return
        }

        // DCC-EX over WiFi is TCP (native commands framed with <...>)
        let conn = NWConnection(host: h, port: p, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleState(state) }
        }

        conn.start(queue: .global(qos: .userInitiated))
        isRunning = true
        appendLog("TCP connect to \(host):\(port) (DCC-EX)")
        receiveLoop()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isRunning = false
        rxBuffer.removeAll()
    }

    func clearLog() {
        logText = ""
    }

    // MARK: - CV Programming Track Operations

    /// Read CV on programming track:
    /// <R cv>  -> response <v cv value> (value -1 means failure) :contentReference[oaicite:4]{index=4}
    func readCV(cv: UInt16) {
        guard (1...1024).contains(cv) else {
            eventsSubject.send(.failure("CV out of range"))
            return
        }
        sendCommand("<R \(cv)>", note: "READ CV \(cv)")
    }

    /// Write CV on programming track:
    /// <W cv value> -> response <r cv value> (value -1 means failure) :contentReference[oaicite:5]{index=5}
    func writeCV(cv: UInt16, value: UInt8) {
        guard (1...1024).contains(cv) else {
            eventsSubject.send(.failure("CV out of range"))
            return
        }
        sendCommand("<W \(cv) \(value)>", note: "WRITE CV \(cv)=\(value)")
    }

    // MARK: - TCP send/receive

    private func sendCommand(_ command: String, note: String? = nil) {
        guard let conn = connection else {
            eventsSubject.send(.failure("Not connected"))
            return
        }
        if let note { appendLog("→ \(note)") }
        appendLog("  tx: \(command)")

        let data = (command).data(using: .utf8) ?? Data()
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Send error: \(error)")
                    self?.eventsSubject.send(.failure("Send error: \(error.localizedDescription)"))
                }
            }
        })
    }

    private func receiveLoop() {
        guard let conn = connection else { return }

        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                if let error {
                    self?.appendLog("Receive error: \(error)")
                    self?.eventsSubject.send(.failure("Receive error: \(error.localizedDescription)"))
                    return
                }

                if let content, !content.isEmpty {
                    self?.rxBuffer.append(content)
                    self?.drainMessagesFromBuffer()
                }

                if isComplete {
                    self?.appendLog("Connection closed by server.")
                    self?.disconnect()
                    return
                }

                self?.receiveLoop()
            }
        }
    }

    /// DCC-EX advises parsing by scanning for '<' and '>' and ignoring anything outside. :contentReference[oaicite:6]{index=6}
    private func drainMessagesFromBuffer() {
        while true {
            guard let start = rxBuffer.firstIndex(of: UInt8(ascii: "<")) else {
                rxBuffer.removeAll(keepingCapacity: true)
                return
            }
            if start > 0 { rxBuffer.removeSubrange(0..<start) }

            guard let end = rxBuffer.firstIndex(of: UInt8(ascii: ">")) else {
                return // wait for more data
            }

            let msgData = rxBuffer.subdata(in: 0...end)
            rxBuffer.removeSubrange(0...end)

            if let msg = String(data: msgData, encoding: .utf8) {
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                appendLog("← rx: \(trimmed)")
                handleMessage(trimmed)
            }
        }
    }

    /// Handles messages like:
    /// <v cv value> for reads, <r cv value> for writes. :contentReference[oaicite:7]{index=7}
    private func handleMessage(_ msg: String) {
        // strip < >
        guard msg.first == "<", msg.last == ">" else { return }
        let inner = msg.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = inner.split(separator: " ").map(String.init)
        guard let head = parts.first else { return }

        switch head {
            case "v": // read response: <v cv value>
                guard parts.count >= 3,
                      let cv = UInt16(parts[1]),
                      let valInt = Int(parts[2]) else { return }
                if valInt < 0 {
                    eventsSubject.send(.failure("Read CV\(cv) failed"))
                } else {
                    eventsSubject.send(.cvReadResult(cv: cv, value: UInt8(clamping: valInt)))
                }

            case "r": // write response: <r cv value>
                guard parts.count >= 3,
                      let cv = UInt16(parts[1]),
                      let valInt = Int(parts[2]) else { return }
                if valInt < 0 {
                    eventsSubject.send(.failure("Write CV\(cv) failed"))
                } else {
                    eventsSubject.send(.cvWriteResult(cv: cv, value: UInt8(clamping: valInt)))
                }

            default:
                // keep for log/debug
                eventsSubject.send(.info(msg))
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
            case .ready:
                appendLog("TCP ready.")
            case .failed(let err):
                appendLog("Connection failed: \(err)")
                eventsSubject.send(.failure("Connection failed: \(err.localizedDescription)"))
                disconnect()
            case .waiting(let err):
                appendLog("Connection waiting: \(err)")
            case .cancelled:
                appendLog("Connection cancelled.")
            default:
                break
        }
    }

    private func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        // (Keep your “last 100 lines” logic here if you already added it.)
        logText += "[\(ts)] \(line)\n"
    }
}

private extension UInt8 {
    init(clamping value: Int) {
        let tmp = UInt8(value)
        self = min(UInt8(0), max(UInt8(255), tmp))
    }
}

