import Foundation
import Network
import Combine

@MainActor
final class DCCEXBackend: ObservableObject, CVBackend {


    @Published private(set) var isRunning = false
    @Published private(set) var logText = ""

    private let eventsSubject = PassthroughSubject<CVEvent, Never>()
    var cvEvents: AnyPublisher<CVEvent, Never> { eventsSubject.eraseToAnyPublisher() }

    private var connection: NWConnection?
    private var rxBuffer = Data()
    private let maxLogLines = 100

    func connect(host: String, port: UInt16) {
        disconnect()
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: .init(host), port: p, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handleState(state) }
        }
        conn.start(queue: .global())
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

    func clearLog() { logText = "" }

    func readCV(locoAddress: UInt16?, cv: UInt16) {
        send("<R \(cv)>", note: "READ CV \(cv)")
    }

    func writeCV(locoAddress: UInt16?, cv: UInt16, value: UInt8) {
        send("<W \(cv) \(value)>", note: "WRITE CV \(cv)=\(value)")
    }

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

    private func send(_ cmd: String, note: String?) {
        guard let conn = connection else { return }
        if let note { appendLog("→ \(note)") }
        appendLog("  tx: \(cmd)")
        conn.send(content: cmd.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            self.rxBuffer.append(data)
            self.parseBuffer()
            self.receiveLoop()
        }
    }

    private func parseBuffer() {
        while let start = rxBuffer.firstIndex(of: 60),
              let end = rxBuffer.firstIndex(of: 62),
              end > start {
            let msg = String(decoding: rxBuffer[start...end], as: UTF8.self)
            rxBuffer.removeSubrange(0...end)
            appendLog("← rx: \(msg)")
            handle(msg)
        }
    }

    private func handle(_ msg: String) {
        let inner = msg.dropFirst().dropLast()
        let parts = inner.split(separator: " ")
        guard parts.count >= 3 else { return }
        let cv = UInt16(parts[1]) ?? 0
        let val = Int(parts[2]) ?? -1

        if msg.hasPrefix("<v") {
            if val >= 0 {
                eventsSubject.send(.cvReadResult(cv: cv, value: UInt8(val)))
            }
        } else if msg.hasPrefix("<r") {
            if val >= 0 {
                eventsSubject.send(.cvWriteResult(cv: cv, value: UInt8(val)))
            }
        }
    }

    private func handleState(_ state: NWConnection.State) {
        if case .ready = state { appendLog("TCP ready") }
    }
}
