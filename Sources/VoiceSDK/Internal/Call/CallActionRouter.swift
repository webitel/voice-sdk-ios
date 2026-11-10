//
//  CallActionRouter.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 23.10.2026.
//

import Foundation


/// A user action on a call that the system call UI (CallKit) must be aware of.
enum CallAction: CustomStringConvertible {
    case answer
    case end
    case mute(Bool)
    case hold(Bool)
    case dtmf(String)

    var description: String {
        switch self {
            case .answer: return "answer"
            case .end: return "end"
            case .mute(let muted): return "mute(\(muted))"
            case .hold(let onHold): return "hold(\(onHold))"
            case .dtmf(let digits): return "dtmf(\(digits))"
        }
    }
}


/// Intercepts `Call` actions before they are performed, so they can go through
/// CallKit first. Called on the caller's thread, after the action was validated.
protocol CallActionRouter: AnyObject {
    /// Returns `true` if the action was taken over; it then comes back through
    /// `CallImpl.performAction(_:)`. Returns `false` to perform it right away.
    func route(_ action: CallAction, for call: CallImpl) -> Bool
}
