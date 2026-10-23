//
//  VoiceManager.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 01.07.2025.
//

import Foundation
import PJSIPKit


/// Except for the call registry (readable from any thread), everything here runs on
/// `SDKQueues.sip`: `CallControlDelegate` methods are invoked by `CallImpl` from that
/// queue and SIP events are dispatched to it by `SipCallbacks`.
final class VoiceManager: CallControlDelegate {

    /// Call waiting: one active call plus one more (held or ringing). Also passed to
    /// PJSIP as `max_calls`, so it answers any further INVITE with 486 by itself.
    static let maxCalls = 2

    let registry = CallRegistry()

    var activeCall: CallImpl? {
        registry.activeCall
    }

    var calls: [CallImpl] {
        registry.calls
    }

    let logger = SDKLogger.make("voice.core.voice")

    private(set) lazy var sipManager: SipManager = SipManager(listener: self)
    private let audioRouter = CallAudioRouter()


    static let shared = VoiceManager()
    private init() {}


    /// See `CallRegistry.insert`.
    func insertCall(
        existing: (CallRegistry.State) -> CallImpl?,
        reject: (CallRegistry.State) -> Bool,
        make: () -> CallImpl
    ) -> (call: CallImpl, outcome: CallRegistry.InsertOutcome) {
        registry.insert(existing: existing, reject: reject, make: make)
    }


    func updateCallSettings(_ settings: CallSettings) {
        SDKQueues.sip.async {
            self.sipManager.updateCallSetting(settings)
        }
    }


    /// Registers the SIP account so the server can deliver an incoming call.
    /// Returns once the registrar answers 2xx.
    func registerForIncoming(_ config: SipConfig) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SDKQueues.sip.async {
                self.sipManager.register(sipConfig: config) { result in
                    continuation.resume(with: result)
                }
            }
        }
    }


    func makeCallFor(_ callId: UUID, _ config: SipConfig, options: CallOptions) async throws {
        try await SDKQueues.onSip {
            // The call may have been disconnected while the SIP config was being fetched.
            guard let _ = self.registry.find(byUUID: callId) else {
                self.logger.warning("Can't find call with id: \(callId)")
                return
            }
            let sipId = try self.sipManager.makeCall(
                sipConfig: config,
                toNumber: options.toNumber,
                toName: options.toName,
                meetingId: options.meetingId,
                type: options.type,
                orientation: options.videoOrientation
            )
            self.registry.assignSipId(sipId, to: callId)
        }
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


    func answerCall(withID id: Int32) throws {
        // Hold the other call before answering, not only on CONFIRMED, so both
        // calls' audio isn't bridged while the 200 OK is being acknowledged.
        if let call = registry.find(bySipId: id) { holdOtherCalls(except: call.id) }
        try sipManager.answerCall(withID: id)
    }


    func disconnectCall(_ target: DisconnectTarget) throws {
        switch target {
            case .local(let uuid): disconnectLocalCall(uuid: uuid)
            case .sip(let sipId): try disconnectSipCall(sipId: sipId)
        }
    }


    func setSpeakerphoneOn(_ enabled: Bool) throws {
        try audioRouter.setSpeakerphoneOn(enabled)
    }


    func switchCamera(withID id: Int32) throws -> Int32 {
        try sipManager.switchCamera(id: id)
    }


    func defaultCaptureDeviceId() -> Int32? {
        sipManager.defaultCaptureDeviceId()
    }


    func syncActiveCaptureDevice(_ deviceId: Int32, callId: Int32) {
        sipManager.syncActiveCaptureDevice(deviceId, callId: callId)
    }


    func setVideoEnabled(withID id: Int32, enabled: Bool) throws {
        try sipManager.setVideoEnabled(enabled, id: id)
    }


    func setLocalVideoPaused(withID id: Int32, paused: Bool) throws {
        try sipManager.setLocalVideoPaused(paused, id: id)
    }


    func setVideoOrientation(withID id: Int32, orientation: VideoOrientation) throws {
        try sipManager.setVideoOrientation(orientation)
    }


    func sendMediaStateInfo(withID id: Int32, audioMuted: Bool, videoMuted: Bool, hold: Bool) throws {
        let body = MediaStateInfo.encode(audioMuted: audioMuted, videoMuted: videoMuted, hold: hold)
        try sipManager.sendInfo(contentType: MediaStateInfo.contentType, body: body, id: id)
    }


    /// `onComplete` is called on `SDKQueues.events`.
    func shutdown(_ onComplete: @escaping () -> Void) {
        SDKQueues.sip.async {
            self.sipManager.destroy {
                SDKQueues.events.async(execute: onComplete)
            }
        }
    }


    // MARK: - Helpers

    func disconnectLocalCall(uuid: UUID) {
        registry.remove(uuid: uuid)
        checkAndDestroySip()
    }


    private func checkAndDestroySip() {
        guard activeCall == nil else { return }
        do {
            try audioRouter.setSpeakerphoneOn(false)
        } catch {
            logger.error("checkAndDestroySip: failed to reset audio route: \(error)")
        }
        self.sipManager.destroy {}
    }


    private func disconnectSipCall(sipId: Int32) throws {
        guard let call = registry.find(bySipId: sipId) else { throw CallError.invalidState(message: "Call not found") }

        let code: UInt32
        switch (call.isAnswered, call.isOutgoing) {
            case (true, _): code = CancelCallCode.NORMAL_CLEARING.rawValue
            case (false, true): code = CancelCallCode.ORIGINATOR_CANCEL.rawValue
            case (false, false): code = CancelCallCode.USER_BUSY_EVERYWHERE.rawValue
        }

        try sipManager.disconnectCall(withID: sipId, code: code)
    }


    /// Only ongoing calls can be held; a ringing one keeps ringing.
    func holdOtherCalls(except exceptId: UUID) {
        for call in registry.holdableCalls(except: exceptId) {
            logger.debug("Holding other call: \(call.id)")
            do {
                try call.performHold(true)
            } catch {
                logger.error("holdOtherCalls: failed to hold \(call.id): \(error)")
            }
        }
    }
}
