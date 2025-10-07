//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// Represents the current state of a call.
public enum CallState: CustomStringConvertible, Equatable {
    /// No active call exists.
    case idle
    
    /// The call is in the process of connecting (e.g., sending INVITE).
    case connecting
    
    /// The remote party is being alerted (the phone is ringing).
    case ringing
    
    /// The call is active and ongoing.
    case ongoing
    
    /// The call has ended. Provides a `CallEndReason` describing
    /// why the call was disconnected.
    case disconnected(CallEndReason)
    
    // MARK: - Equatable
    
    /// Compares two call states for equality.
    /// For `.disconnected`, it only compares the case, not the reason.
    public static func == (lhs: CallState, rhs: CallState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.ringing, .ringing),
             (.ongoing, .ongoing):
            return true
        case (.disconnected, .disconnected):
            return true
        default:
            return false
        }
    }

    // MARK: - CustomStringConvertible
    
    /// A human-readable description of the current call state.
    public var description: String {
        switch self {
        case .idle:
            return "IDLE"
        case .connecting:
            return "Connecting"
        case .ringing:
            return "Ringing"
        case .ongoing:
            return "Ongoing"
        case .disconnected(let reason):
            return """
            Disconnected( \
            type: \(reason.type.rawValue), \
            message: \"\(reason.message)\", \
            category: \(reason.category.rawValue) \
            )
            """
        }
    }
}
