//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 01.07.2025.
//

import Foundation
import PJSIPKit



final class VoiceManager: CallControlDelegate, SipEventListener {
    private var callsByUUID: [UUID: WebitelCall] = [:]
    private var callsBySipId: [Int32: UUID] = [:]
    private(set) var activeCall: WebitelCall?
    
    private lazy var sipManager: SipManager = SipManager(listener: self)
    
    static let shared = VoiceManager()
    private init() {}
    
    
    func newCall(_ call: WebitelCall) {
        callsByUUID[call.id] = call
        if activeCall == nil { activeCall = call }
    }
    
    
    func updateCallSettings(_ settings: CallSettings) {
        sipManager.updateCallSetting(settings)
    }
    
    
    func makeAudioCallFor(_ callId: UUID, _ config: SipConfig) throws {
        guard let _ = findCall(byUUID: callId) else {
            WLog.shared.warning("Can't find call with id: \(callId)")
            return
        }
        let sipId = try sipManager.makeCall(sipConfig: config, toNumber: "service")
        assignSipId(sipId, to: callId)
    }
    
    
    // MARK: - CallControlDelegate
    
    func muteCall(withID id: Int32, muted: Bool) throws {
        try sipManager.setMute(muted, id: id)
    }
    
    
    func holdCall(withID id: Int32, onHold: Bool) throws {
        try sipManager.setHold(onHold, id: id)
    }
    
    
    func sendDTMF(withID id: Int32, digits: String) throws {
        try sipManager.sendDTMF(digits, id: id)
    }
    
    
    func disconnectCall(_ target: DisconnectTarget) throws {
        switch target {
            case .local(let uuid): disconnectLocalCall(uuid: uuid)
            case .sip(let sipId): try disconnectSipCall(sipId: sipId)
        }
    }
    
    
    func shutdown(_ onComplete: @escaping () -> Void) {
        sipManager.destroy(onComplete)
    }
    
    
    // MARK: - SIP Events
    
    func onCallState(state: pjsip_inv_state, sipId: Int32, lastStatusCode: Int, lastReason: String?) {
        guard let call = findCall(bySipId: sipId) else {
            WLog.shared.warning("CALL NOT FOUND BY INTID: \(sipId); state: \(state)")
            return
        }
        
        switch state {
            case PJSIP_INV_STATE_NULL, PJSIP_INV_STATE_CALLING, PJSIP_INV_STATE_CONNECTING:
                WLog.shared.debug("Call connecting: \(state.rawValue)")
                call.upateState(.connecting)
                if state == PJSIP_INV_STATE_CONNECTING { sipManager.startAudio() }
                
            case PJSIP_INV_STATE_EARLY:
                WLog.shared.debug("Call early: \(state.rawValue)")
                call.upateState(call.isOutgoing ? .ringing : .connecting)
                
            case PJSIP_INV_STATE_INCOMING:
                WLog.shared.debug("Incoming call: \(state.rawValue)")
                call.upateState(.ringing)
                
            case PJSIP_INV_STATE_CONFIRMED:
                WLog.shared.debug("Call confirmed: \(state.rawValue)")
                holdOtherCalls(except: call.id)
                call.onConfirmedPJSIP()
                
            case PJSIP_INV_STATE_DISCONNECTED:
                call.upateState(.disconnected(CallEndReason.from(code: lastStatusCode, lastReason)))
                disconnectLocalCall(uuid: call.id)
                
            default: break
        }
    }
    
    
    func onCallMediaState(sipId: Int32) {
        guard let call = findCall(bySipId: sipId) else {
            WLog.shared.warning("onCallMediaState: CALL NOT FOUND BY INTID: \(sipId)")
            return
        }
        
        var ci = pjsua_call_info()
        guard pjsua_call_get_info(sipId, &ci) == PJ_SUCCESS.rawValue else { return }
        let mediaInfos: [pjsua_call_media_info] = tupleToArray(tuple: ci.media)
        
        for cmi in mediaInfos where cmi.type == PJMEDIA_TYPE_AUDIO {
            switch cmi.status {
                case PJSUA_CALL_MEDIA_LOCAL_HOLD:
                    call.isHoldInProgress = false
                    call.onHoldCallPJSIP(onHold: true)
                    
                case PJSUA_CALL_MEDIA_ACTIVE:
                    call.isHoldInProgress = false
                    if activeCall?.id != call.id { activeCall = call }
                    holdOtherCalls(except: call.id)
                    call.onHoldCallPJSIP(onHold: false)
                    
                default: break
            }
        }
        
        // Connect audio ports
        for (i, cmi) in mediaInfos.enumerated() where cmi.type == PJMEDIA_TYPE_AUDIO &&
        (cmi.status == PJSUA_CALL_MEDIA_ACTIVE || cmi.status == PJSUA_CALL_MEDIA_REMOTE_HOLD) {
            
            let callConfSlot = mediaInfos[i].stream.aud.conf_slot
            pjsua_conf_connect(callConfSlot, 0)
            pjsua_conf_connect(0, callConfSlot)
        }
        
        if call.isMuted {
            do { try sipManager.setMute(true, id: call.sipId) }
            catch {
                WLog.shared.error(
                    "Error while reconnecting audio with mute: \(error)\n\(Thread.callStackSymbols.joined(separator: "\n"))"
                )
            }
        }
    }
    
    
    // MARK: - Private Helpers
    
    private func disconnectLocalCall(uuid: UUID) {
        removeCall(uuid: uuid)
        if activeCall?.id == uuid { activeCall = callsByUUID.values.first }
        checkAndDestroySip()
    }
    
    
    private func checkAndDestroySip() {
        guard activeCall == nil else { return }
        self.sipManager.destroy {}
    }
    
    
    private func disconnectSipCall(sipId: Int32) throws {
        guard let call = findCall(bySipId: sipId) else { throw CallError.invalidState(message: "Call not found") }
        
        let code: UInt32
        switch (call.isAnswered, call.isOutgoing) {
            case (true, _): code = CancelCallCode.NORMAL_CLEARING.rawValue
            case (false, true): code = CancelCallCode.ORIGINATOR_CANCEL.rawValue
            case (false, false): code = CancelCallCode.USER_BUSY_EVERYWHERE.rawValue
        }
        
        try sipManager.disconnectCall(withID: sipId, code: code)
    }
    
    
    private func holdOtherCalls(except exceptId: UUID) {
        for call in callsByUUID.values where call.id != exceptId && call.sipId >= 0 {
            WLog.shared.debug("Holding other call: \(call.id)")
            try? sipManager.setHold(true, id: call.sipId)
        }
    }
    
    
    private func removeCall(uuid: UUID) {
        guard let call = callsByUUID.removeValue(forKey: uuid) else { return }
        callsBySipId.removeValue(forKey: call.sipId)
    }
    
    
    private func findCall(byUUID uuid: UUID) -> WebitelCall? {
        callsByUUID[uuid]
    }
    
    
    private func findCall(bySipId sipId: Int32) -> WebitelCall? {
        guard let uuid = callsBySipId[sipId] else { return nil }
        return callsByUUID[uuid]
    }
    
    
    private func assignSipId(_ sipId: Int32, to uuid: UUID) {
        guard let call = callsByUUID[uuid] else { return }
        call.sipId = sipId
        callsBySipId[sipId] = uuid
    }
    
    
    private func tupleToArray<Tuple, Value>(tuple: Tuple) -> [Value] {
        Mirror(reflecting: tuple).children.compactMap { $0.value as? Value }
    }
}

