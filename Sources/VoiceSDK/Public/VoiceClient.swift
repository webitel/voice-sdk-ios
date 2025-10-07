//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// A high-level interface for managing voice calls.
///
/// `VoiceClient` handles user identity, authentication tokens,
/// call setup, configuration, and lifecycle management.
public protocol VoiceClient {
    
    /// The currently active call, if any.
    var activeCall: Call? { get }

    
    /// Assigns the user identity to the client.
    ///
    /// - Parameter user: A `User` object representing the identity
    ///   used for outgoing calls.
    func setUser(_ user: User)

    
    /// Assigns a JWT authentication token to the client.
    ///
    /// The token is stored internally and used when creating new calls.
    ///
    /// - Parameter token: A valid JWT string.
    func setJWT(_ token: String)
    
    
    /// Creates and starts a new audio call using the previously configured
    /// user or JWT.
    ///
    /// - Parameter listener: A `CallListener` to receive call events
    ///   (e.g. ringing, connected, ended).
    /// - Returns: A `Call` instance representing the ongoing call.
    func makeAudioCall(listener: CallListener) -> Call

    
    /// Creates and starts a new audio call with a specific JWT.
    ///
    /// This overload allows overriding the stored token for a single call.
    ///
    /// - Parameters:
    ///   - jwt: A JWT string to be used for this call only.
    ///   - listener: A `CallListener` to receive call events.
    /// - Returns: A `Call` instance representing the ongoing call.
    func makeAudioCall(jwt: String, listener: CallListener) -> Call
    
    
    /// Configures the client with general call-related settings.
    ///
    /// - Parameter settings: A `CallSettings` object that controls
    ///   audio, networking, and other call options.
    func configure(_ settings: CallSettings)

    
    /// Shuts down the client and releases its resources.
    ///
    /// - Parameter onComplete: A closure that is called once shutdown
    ///   is fully complete.
    func shutdown(onComplete: @escaping () -> Void)
}
