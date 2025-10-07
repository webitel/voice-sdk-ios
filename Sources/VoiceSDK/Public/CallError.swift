//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//

import Foundation


/// Represents different error cases that can occur during
/// the lifecycle of a call or when interacting with SIP services.
enum CallError: Error {
    /// Indicates that a response from the server or SIP stack
    /// was malformed, missing fields, or otherwise unusable.
    case invalidResponse(message: String)
    
    /// Indicates that the operation could not be performed
    /// because the call was not in the required state.
    ///
    /// For example, trying to mute while the call is not `.ongoing`,
    /// or attempting an action in `.idle` or `.disconnected` states.
    case invalidState(message: String)
    
    /// Indicates that authentication failed, for example due
    /// to an invalid or expired token, or missing credentials.
    case unauthorized(message: String)
    
    /// Indicates that the provided SIP or server URL is invalid
    /// or could not be parsed correctly.
    case invalidURL(message: String)
    
    /// Represents a generic SIP protocol error, usually when
    /// a non-success SIP status code was returned.
    case sipError(message: String)
    
    /// Represents an unknown or unexpected error that does not
    /// fit into other categories. Provides a message and a code
    /// for additional debugging information.
    case unknown(message: String, code: Int)
}
