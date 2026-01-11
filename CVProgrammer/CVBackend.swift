import Foundation
import Combine

enum CVEvent: Equatable {
    case cvReadResult(cv: UInt16, value: UInt8)
    case cvWriteResult(cv: UInt16, value: UInt8)
    case nack
    case failure(String)
    case info(String)
}

@MainActor
protocol CVBackend: ObservableObject {
    var isRunning: Bool { get }
    var logText: String { get }
    var cvEvents: AnyPublisher<CVEvent, Never> { get }

    func connect(host: String, port: UInt16)
    func disconnect()

    func readCV(locoAddress: UInt16?, cv: UInt8)
    func writeCV(locoAddress: UInt16?, cv: UInt8, value: UInt8)

    func clearLog()
    func appendLog(_ line: String)
    func appendExternalLog(_ line: String)
}
