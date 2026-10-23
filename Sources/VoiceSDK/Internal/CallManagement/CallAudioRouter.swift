//
//  CallAudioRouter.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import Foundation
import AVFAudio


/// Routes call audio between the earpiece and the loudspeaker.
///
/// This is a system audio-routing concern, not a SIP/media one, so it is
/// implemented directly on top of `AVAudioSession` rather than PJSIP.
final class CallAudioRouter {
    private let logger = SDKLogger.make("voice.core.audioRouter")

    func setSpeakerphoneOn(_ enabled: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            logger.error("setSpeakerphoneOn: \(enabled), \(error)")
            throw CallError.invalidState(message: "Failed to override audio output port: \(error.localizedDescription)")
        }
    }
}
