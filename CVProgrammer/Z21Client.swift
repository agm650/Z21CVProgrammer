//
//  Z21Client.swift
//  Z21CVProgrammer
//
//  Created by Luc Dandoy on 22/12/2025.
//
import Foundation
import Network
import Combine

@MainActor
final class Z21Client: ObservableObject, CVBackend {

    internal init(cvEvents: AnyPublisher<CVEvent, Never> = Empty().eraseToAnyPublisher(),
                  isRunning: Bool = false,
                  logText: String = "",
                  connection: NWConnection? = nil) {
        self.cvEvents = cvEvents
        self.isRunning = isRunning
        self.logText = logText
        self.connection = connection
    }

    var cvEvents: AnyPublisher<CVEvent, Never>

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var logText: String = ""

    private let maxLogLines = 100

    private let eventsSubject = PassthroughSubject<any CVBackend, Never>()
    var events: AnyPublisher<any CVBackend, Never> { eventsSubject.eraseToAnyPublisher() }

    private var connection: NWConnection?

    func connect(host: String, port: UInt16) {
        disconnect()

        let h = NWEndpoint.Host(host)
        guard let p = NWEndpoint.Port(rawValue: port) else {
            appendLog("Invalid port: \(port)")
            return
        }

        let conn = NWConnection(host: h, port: p, using: .udp)
        self.connection = conn

        conn.start(queue: .global())
        isRunning = true

        appendLog("Starting UDP connection to \(host):\(port)")
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isRunning = false
    }

    func clearLog() {
        logText = ""
    }

    func readCV(locoAddress: UInt16?, cv: UInt16) {
        guard let locoAddress else { return }
        let pkt = Z21Protocol.makePOMReadBytePacket(locoAddress: locoAddress, cvAddress0Based: cv - 1)
        send(pkt)
    }

    func writeCV(locoAddress: UInt16?, cv: UInt16, value: UInt8) {
        guard let locoAddress else { return }
        let pkt = Z21Protocol.makePOMWriteBytePacket(locoAddress: locoAddress, cvAddress0Based: cv - 1, value: value)
        send(pkt)
    }

    private func send(_ data: Data, note: String? = nil) {
        guard let conn = connection else {
            appendLog("Not connected; cannot send.")
            return
        }

        if let note { appendLog("→ \(note)") }
        appendLog("  bytes: \(data.hexString)")

        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                if let error { self?.appendLog("Send error: \(error)") }
            }
        })
    }
//
//    private func beginReceiveLoop() {
//        guard let conn = connection else { return }
//
//        conn.receiveMessage { [weak self] content, _, _, error in
//            Task { @MainActor in
//                if let error {
//                    self?.appendLog("Receive error: \(error)")
//                } else if let content, !content.isEmpty {
//                    self?.appendLog("← RX bytes: \(content.hexString)")
//
//                    let event = Z21Protocol.parseInbound(content)
//                    self?.eventsSubject.send(event)
//
//                    self?.appendLog("  event: \(event.description)")
//                }
//                self?.beginReceiveLoop()
//            }
//        }
//    }
//
//    private func handleState(_ state: NWConnection.State) {
//        switch state {
//            case .ready:
//                appendLog("UDP ready.")
//            case .failed(let err):
//                appendLog("Connection failed: \(err)")
//                disconnect()
//            case .waiting(let err):
//                appendLog("Connection waiting: \(err)")
//            case .cancelled:
//                appendLog("Connection cancelled.")
//            default:
//                break
//        }
//    }

    func appendLog(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let newLine = "[\(ts)] \(line)"

        var lines = logText.split(separator: "\n", omittingEmptySubsequences: true)
        lines.append(Substring(newLine))

        // ✅ Keep only the last N lines
        if lines.count > maxLogLines {
            lines = lines.suffix(maxLogLines)
        }

        logText = lines.joined(separator: "\n") + "\n"
    }

    func appendExternalLog(_ line: String) {
        appendLog(line)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

enum Z21Event: Equatable {
    case cvResult(cvAddress0Based: UInt16, value: UInt8)
    case cvNack
    case unknown

    var description: String {
        switch self {
            case .cvResult(let cv0, let value):
                return "CV_RESULT cv=\(cv0 + 1) value=\(value)"
            case .cvNack:
                return "CV_NACK"
            case .unknown:
                return "UNKNOWN"
        }
    }
}
