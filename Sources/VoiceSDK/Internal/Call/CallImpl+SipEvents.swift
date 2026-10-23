//
//  CallImpl+SipEvents.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import Foundation
import PJSIPKit


// MARK: - Events from `VoiceManager` (all on `SDKQueues.sip`)

extension CallImpl {

    // MARK: Incoming call

    /// Ends the incoming call with `.requestTimeout` if its INVITE hasn't arrived within `interval`.
    func startIncomingTimeout(_ interval: TimeInterval) {
        SDKQueues.sip.async { [self] in
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.sipId < 0 else { return }
                if case .disconnected = self.state { return }
                self.logger.warning("Incoming call INVITE not received within \(interval)s")
                self.cancelTask()
                self.disconnectWithReason(callEndReason: .from(code: 408, "Incoming call was not received in time"))
            }
            incomingTimeout = item
            SDKQueues.sip.asyncAfter(deadline: .now() + interval, execute: item)
        }
    }


    /// The SIP INVITE for this incoming call arrived and `sipId` is assigned.
    func onIncomingInviteReceived() {
        SDKQueues.assertOnSip()
        incomingTimeout?.cancel()
        incomingTimeout = nil

        guard pendingAnswer else { return }
        pendingAnswer = false
        do {
            try delegate?.answerCall(withID: sipId)
        } catch {
            logger.error("onIncomingInviteReceived: pending answer failed – \(error)")
            disconnectWithReason(callEndReason: .from(code: -1, "\(error)"))
        }
    }


    // MARK: Call state & media

    func onHoldCallPJSIP(onHold: Bool) {
        if isOnHold == onHold {
            return
        }
        isOnHold = onHold
        notify(.localMedia(.holdChanged(callId: id, isOnHold: isOnHold)))
        sendMediaStateInfo()
    }


    func onConfirmedPJSIP() {
        let date = NSDate()
        answeredAt = Int64(date.timeIntervalSince1970)
        updateState(.ongoing)
        autoEnableSpeakerForVideo()
        sendMediaStateInfo()
    }


    /// The remote party's media state, reported via a SIP INFO packet — see `MediaStateInfo`.
    /// Each parameter is `nil` if that field was absent from the payload (unchanged).
    func onRemoteMediaStateInfo(audioMuted: Bool?, videoMuted: Bool?, hold: Bool?) {
        if let audioMuted, audioMuted != isRemoteMuted {
            isRemoteMuted = audioMuted
            notify(.remoteMedia(.muteChanged(callId: id, isMuted: audioMuted)))
        }
        if let hold, hold != isRemoteOnHold {
            isRemoteOnHold = hold
            notify(.remoteMedia(.holdChanged(callId: id, isOnHold: hold)))
        }
        if let videoMuted, videoMuted != isRemoteVideoPaused {
            isRemoteVideoPaused = videoMuted
            notify(.remoteMedia(.videoPausedChanged(callId: id, isPaused: videoMuted)))
        }
    }


    // MARK: Video

    func onShowLocalVideo(_ cmi: pjsua_call_media_info) {
        logger.debug("onShowLocalVideo() called")

        guard video.startLocalPreview() else { return }

        isLocalVideoActive = true
        notify(.video(.stateChanged(callId: id, state: videoState)))

        if isLocalVideoPaused {
            // A pause requested before local video became active (e.g. during
            // .ringing) was only recorded on `isLocalVideoPaused` — now that the
            // encoding stream actually exists, apply it for real.
            do {
                try delegate?.setLocalVideoPaused(withID: sipId, paused: true)
            } catch {
                logger.error("onShowLocalVideo: failed to re-apply local video pause: \(error)")
            }
        }

        if let preview = video.attachLocalPreview() {
            notify(.video(.localViewReady(callId: id, view: preview)))
        }
    }


    func onShowRemoteVideo(_ cmi: pjsua_call_media_info) {
        guard let view = video.showRemoteVideo(cmi) else { return }

        isRemoteVideoActive = true
        notify(.video(.stateChanged(callId: id, state: videoState)))
        notify(.video(.remoteViewReady(callId: id, view: view)))
    }


    /// PJSIP pauses the video decode port on hold instead of destroying it, so the same
    /// window/`UIView` is typically handed back on resume. Reset the identity-dedup guard
    /// in `onShowRemoteVideo` here so the next `PJSUA_CALL_MEDIA_ACTIVE` always re-fires
    /// `.remoteViewReady` instead of being silently swallowed by the same-view check.
    func onRemoteVideoHoldChanged(onHold: Bool) {
        guard onHold, isRemoteVideoActive || video.hasRemoteView else { return }
        video.clearRemoteView()
        isRemoteVideoActive = false
        notify(.video(.stateChanged(callId: id, state: videoState)))
    }


    func onRemoteVideoSizeChanged(width: Int, height: Int) {
        guard video.updateRemoteVideoSize(width: width, height: height) else { return }
        notify(.video(.sizeChanged(callId: id, isLocal: false, width: width, height: height)))
    }


    func stopPreviewVideo() {
        logger.debug("stopPreviewVideo: stop showing local/remote video")
        isLocalVideoActive = false
        isRemoteVideoActive = false
        isRemoteMuted = false
        isRemoteOnHold = false
        isRemoteVideoPaused = false
        video.stop()
    }
}
