//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


public enum LogLevel: Int, Codable, CaseIterable, @unchecked Sendable {
    /// Appropriate for messages that contain information normally of use only when
    /// tracing the execution of a program.
    case trace

    /// Appropriate for messages that contain information normally of use only when
    /// debugging a program.
    case debug

    /// Appropriate for informational messages.
    case info

    /// Appropriate for conditions that are not error conditions, but that may require
    /// special handling.
    case notice

    /// Appropriate for messages that are not error conditions, but more severe than
    /// `.notice`.
    case warning

    /// Appropriate for error conditions.
    case error

    /// Appropriate for critical error conditions that usually require immediate
    /// attention.
    ///
    /// When a `critical` message is logged, the logging backend (`LogHandler`) is free to perform
    /// more heavy-weight operations to capture system state (such as capturing stack traces) to facilitate
    /// debugging.
    case critical
}
