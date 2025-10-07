//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


public protocol Call {
    var id: UUID { get }
    
    /// Current state of the call (e.g. ringing, active, ended).
    var state: CallState { get }

    /// Indicates whether the local microphone is muted.
    var isMuted: Bool { get }

    /// Indicates whether the call is currently on hold.
    var isOnHold: Bool { get }

    /// Timestamp in milliseconds when the call was answered.
    var answeredAt: Int64 { get }

    /// True if the call was initiated by the local user (outgoing).
    var isOutgoing: Bool { get }

    /// Mute or unmute the microphone.
    func mute(_ mute: Bool) throws

    /// Put the call on hold or resume it.
    func hold(_ hold: Bool) throws

    /// Send DTMF digits during the call.
    func sendDTMF(_ digits: String) throws

    /// Disconnect or hang up the call.
    func disconnect() throws

    /// Add a listener for call events.
    func addListener(_ listener: CallListener)

    /// Remove a specific listener.
    func removeListener(_ listener: CallListener)

    /// Remove all listeners.
    func removeAllListeners()
}
