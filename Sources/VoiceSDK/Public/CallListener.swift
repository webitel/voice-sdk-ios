//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// A listener protocol for receiving updates about call state
/// and other important call-related events.
public protocol CallListener: AnyObject {
    /// Called whenever the state of the call changes.
    ///
    /// Typical state transitions include:
    /// - `.connecting` → `.ringing`
    /// - `.ringing` → `.ongoing`
    /// - `.ongoing` → `.disconnected`
    ///
    /// - Parameters:
    ///   - call: The call instance whose state changed.
    ///   - state: The new state of the call.
    func onCallStateChanged(call: Call, state: CallState)

    /// Called when the hold status of the call changes.
    ///
    /// - Parameters:
    ///   - call: The call instance whose hold status changed.
    ///   - isOnHold: `true` if the call is now on hold, `false` otherwise.
    func onHoldChanged(call: Call, isOnHold: Bool)
}


/// Provides default (no-op) implementations for optional methods
/// in `CallListener`, so conforming types can override only what they need.
public extension CallListener {
    func onHoldChanged(call: Call, isOnHold: Bool) {
        // Optional to implement
    }
}
