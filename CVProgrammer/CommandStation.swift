//
//  CommandStation.swift
//  CVProgrammer
//
//  Created by Luc Dandoy on 10/01/2026.
//

import Combine

protocol CommandStation: ObservableObject {
    var isRunning: Bool { get }
    var logText: String { get }

    var events: AnyPublisher<CVEvent, Never> { get }

    func connect(host: String, port: UInt16)
    func disconnect()

    /// Programming-track read/write (service mode)
    func readCV(cv: UInt16)       // 1-based
    func writeCV(cv: UInt16, value: UInt8)

    func clearLog()
}

