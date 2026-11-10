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
///
/// The route can also change outside the SDK — the CallKit speaker button,
/// Control Center, Bluetooth devices — so the actual route is the source of truth
/// and every change is reported through `onRouteChange` on `SDKQueues.sip`.
final class CallAudioRouter {
    private let logger = SDKLogger.make("voice.core.audioRouter")
    private var routeObserver: NSObjectProtocol?


    init(onRouteChange: @escaping (_ isSpeakerActive: Bool) -> Void) {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            self.logRouteChange(notification)
            let isSpeakerActive = self.isSpeakerActive
            SDKQueues.sip.async { onRouteChange(isSpeakerActive) }
        }
    }


    deinit {
        routeObserver.map(NotificationCenter.default.removeObserver)
    }


    var isSpeakerActive: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }


    func setSpeakerphoneOn(_ enabled: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(enabled ? .speaker : .none)
        } catch {
            logger.error("setSpeakerphoneOn: \(enabled), \(error)")
            throw CallError.invalidState(message: "Failed to override audio output port: \(error.localizedDescription)")
        }
    }


    private func logRouteChange(_ notification: Notification) {
        let session = AVAudioSession.sharedInstance()
        let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
        logger.debug("""
            route changed: reason \(reason.map(String.init) ?? "?"), outputs [\(outputs)], \
            category \(session.category.rawValue), mode \(session.mode.rawValue)
            """)
    }
}
