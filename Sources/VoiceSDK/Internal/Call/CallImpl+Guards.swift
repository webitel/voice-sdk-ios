//
//  CallImpl+Guards.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import Foundation


// MARK: - State preconditions for `Call` operations

extension CallImpl {

    func ensureCallOngoing() throws {
        guard case .ongoing = state else {
            let message = "Call is not in an ongoing state. Current state: \(state)"
            logger.error("\(message)")
            throw CallError.invalidState(message: message)
        }
    }


    /// Looser than `ensureCallOngoing()` — allows mute/local-video-pause to be
    /// requested as soon as the call exists (including `.connecting`/`.ringing`,
    /// before any media session is negotiated), matching the Android SDK. The
    /// desired state is recorded even if there's no active media yet to apply
    /// it to; it's re-applied for real once media activates.
    func ensureMediaControlAllowed() throws {
        switch state {
        case .idle, .disconnected:
            let message = "Call is not active. Current state: \(state)"
            logger.error("\(message)")
            throw CallError.invalidState(message: message)
        case .connecting, .ringing, .ongoing:
            return
        }
    }


    func ensureHoldAllowed() throws {
        try ensureCallOngoing()
        try ensureSipIdValid()

        if isHoldInProgress {
            let message = "Hold/unhold operation already in progress."
            logger.error("\(message)")
            throw CallError.invalidState(message: message)
        }
    }


    func ensureHasVideo() throws {
        guard hasVideo else {
            throw CallError.invalidState(message: "Call has no video")
        }
    }


    func ensureSipIdValid() throws {
        guard sipId >= 0 else {
            let message = "SIP id not created yet."
            logger.error("\(message)")
            throw CallError.invalidState(message: message)
        }
    }
}
