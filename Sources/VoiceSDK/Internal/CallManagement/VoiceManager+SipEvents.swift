//
//  VoiceManager+SipEvents.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 23.10.2026.
//

import Foundation
import PJSIPKit


// MARK: - SipEventListener

extension VoiceManager: SipEventListener {

    func onCallState(state: pjsip_inv_state, sipId: Int32, lastStatusCode: Int, lastReason: String?) {
        SDKQueues.assertOnSip()
        guard let call = registry.find(bySipId: sipId) else {
            logger.warning("CALL NOT FOUND BY INTID: \(sipId); state: \(state)")
            return
        }

        switch state {
            case PJSIP_INV_STATE_NULL, PJSIP_INV_STATE_CALLING, PJSIP_INV_STATE_CONNECTING:
                logger.debug("Call connecting: \(state.rawValue)")
                call.updateState(.connecting)
                // With another call already ongoing the sound device is in use;
                // re-setting it would interrupt that call's audio.
                if state == PJSIP_INV_STATE_CONNECTING && !registry.hasOtherOngoingCall(except: call.id) {
                    sipManager.startAudio()
                }

            case PJSIP_INV_STATE_EARLY:
                logger.debug("Call early: \(state.rawValue)")
                // Incoming calls are already `.ringing` (or `.connecting` if answered
                // before the INVITE arrived); our own 180 must not change that.
                if call.isOutgoing { call.updateState(.ringing) }

            case PJSIP_INV_STATE_INCOMING:
                logger.debug("Incoming call: \(state.rawValue)")
                if call.state == .idle { call.updateState(.ringing) }

            case PJSIP_INV_STATE_CONFIRMED:
                logger.debug("Call confirmed: \(state.rawValue)")
                holdOtherCalls(except: call.id)
                call.onConfirmedPJSIP()

            case PJSIP_INV_STATE_DISCONNECTED:
                call.updateState(.disconnected(CallEndReason.from(code: lastStatusCode, lastReason)))
                // Before `disconnectLocalCall`, which may destroy pjsua — the preview
                // can only be stopped while the stack is still running.
                call.stopPreviewVideo()
                disconnectLocalCall(uuid: call.id)

            default: break
        }
    }


    func onCallMediaState(sipId: Int32) {
        SDKQueues.assertOnSip()
        guard isPjsuaRunning else { return }
        guard let call = registry.find(bySipId: sipId) else {
            logger.warning("onCallMediaState: CALL NOT FOUND BY INTID: \(sipId)")
            return
        }

        registerPJThread()
        var ci = pjsua_call_info()
        guard pjsua_call_get_info(sipId, &ci) == PJ_SUCCESS.rawValue else { return }

        let mediaInfos: [pjsua_call_media_info] = tupleToArray(ci.media)

        // AUDIO
        for cmi in mediaInfos where cmi.type == PJMEDIA_TYPE_AUDIO {
            switch cmi.status {
            case PJSUA_CALL_MEDIA_LOCAL_HOLD:
                call.isHoldInProgress = false
                call.onHoldCallPJSIP(onHold: true)

            case PJSUA_CALL_MEDIA_ACTIVE:
                call.isHoldInProgress = false
                registry.setActive(call)
                holdOtherCalls(except: call.id)
                call.onHoldCallPJSIP(onHold: false)

            default: break
            }
        }

        // Connect audio ports
        for (i, cmi) in mediaInfos.enumerated() where cmi.type == PJMEDIA_TYPE_AUDIO &&
            (cmi.status == PJSUA_CALL_MEDIA_ACTIVE || cmi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {

            let callConfSlot = mediaInfos[i].stream.aud.conf_slot
            guard callConfSlot != PJSUA_INVALID_ID.rawValue else { continue }
            pjsua_conf_connect(callConfSlot, 0)
            pjsua_conf_connect(0, callConfSlot)
        }

        if call.isMuted {
            do { try sipManager.setMute(true, id: call.sipId) }
            catch {
                logger.error("Error while reconnecting audio with mute: \(error)\n\(Thread.callStackSymbols.joined(separator: "\n"))")
            }
        }

        // VIDEO — hold: PJSIP pauses the decode port rather than destroying the
        // window/UIView, so the remote-view dedup guard in onShowRemoteVideo must be
        // reset here or the post-resume ACTIVE callback below is silently swallowed.
        for cmi in mediaInfos where
            cmi.type == PJMEDIA_TYPE_VIDEO &&
            (cmi.status == PJSUA_CALL_MEDIA_LOCAL_HOLD || cmi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
            call.onRemoteVideoHoldChanged(onHold: true)
        }

        // VIDEO
        for cmi in mediaInfos where
            cmi.type == PJMEDIA_TYPE_VIDEO &&
            cmi.status == PJSUA_CALL_MEDIA_ACTIVE &&
            (cmi.dir.rawValue & PJMEDIA_DIR_ENCODING.rawValue) != 0 {

            logger.debug("onCallMediaState: video active, showing local video")
            call.onShowLocalVideo(cmi)
        }

        // Attach the renderer whenever the decoding stream becomes active.
        // CallImpl dedupes notifications by the actual UIView instance, not by
        // PJSIP's reusable numeric window id.
        for cmi in mediaInfos where
            cmi.type == PJMEDIA_TYPE_VIDEO &&
            cmi.status == PJSUA_CALL_MEDIA_ACTIVE &&
            (cmi.dir.rawValue & PJMEDIA_DIR_DECODING.rawValue) != 0 {

            logger.debug("onCallMediaState: video active, showing remote video")
            call.onShowRemoteVideo(cmi)
        }
    }


    func onRemoteVideoFormatChanged(
        sipId: Int32,
        mediaIndex: Int,
        newWidth: UInt32,
        newHeight: UInt32
    ) {
        SDKQueues.assertOnSip()
        guard isPjsuaRunning else { return }
        guard let call = registry.find(bySipId: sipId) else {
            logger.warning("onRemoteVideoFormatChanged: CALL NOT FOUND BY INTID: \(sipId)")
            return
        }

        // Fresh media info: the render window from the media-thread event may already be gone.
        registerPJThread()
        var ci = pjsua_call_info()
        guard pjsua_call_get_info(sipId, &ci) == PJ_SUCCESS.rawValue,
              mediaIndex < Int(ci.media_cnt),
              let cmi = getMediaInfo(ci, index: mediaIndex),
              cmi.type == PJMEDIA_TYPE_VIDEO,
              cmi.status == PJSUA_CALL_MEDIA_ACTIVE,
              (cmi.dir.rawValue & PJMEDIA_DIR_DECODING.rawValue) != 0 else {
            return
        }

        call.onShowRemoteVideo(cmi)
        call.onRemoteVideoSizeChanged(width: Int(newWidth), height: Int(newHeight))
    }


    func onIncomingCall(sipId: Int32, callUuid: UUID?) {
        SDKQueues.assertOnSip()
        guard isPjsuaRunning else { return }
        guard let callUuid,
              let call = registry.find(byUUID: callUuid),
              !call.isOutgoing,
              call.sipId < 0 else {
            logger.warning("onIncomingCall: no pending incoming call for X-Webitel-Uuid \(callUuid?.uuidString ?? "nil"), declining")
            try? sipManager.disconnectCall(withID: sipId, code: CancelCallCode.DECLINE.rawValue)
            return
        }

        logger.debug("onIncomingCall: INVITE matched call \(callUuid), sipId: \(sipId)")
        registry.assignSipId(sipId, to: callUuid)
        sipManager.sendRinging(withID: sipId)
        call.onIncomingInviteReceived()
    }


    func onRegistrationState(code: Int, reason: String?) {
        sipManager.onRegistrationState(code: code, reason: reason)
    }


    func onIncomingInfo(sipId: Int32, wholeMsg: String) {
        SDKQueues.assertOnSip()
        guard let call = registry.find(bySipId: sipId) else {
            logger.warning("onIncomingInfo: CALL NOT FOUND BY INTID: \(sipId)")
            return
        }
        guard let info = MediaStateInfo.parse(fromWholeMessage: wholeMsg) else { return }
        call.onRemoteMediaStateInfo(audioMuted: info.audioMuted, videoMuted: info.videoMuted, hold: info.hold)
    }
}
