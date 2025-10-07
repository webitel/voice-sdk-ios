//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//

import Foundation


class WebitelCall: Call {
    private var listeners = NSHashTable<AnyObject>.weakObjects()
    private var apiConfigTask: Task<Void, Never>? = nil
    private weak var delegate: (CallControlDelegate)?
    
    let id: UUID = UUID()
    var sipId: Int32 = -1
    var isHoldInProgress = false
    
    var state: CallState = .idle
    var isMuted: Bool = false
    var isOnHold: Bool = false
    var isOutgoing: Bool = false
    var answeredAt: Int64 = 0
    
    var isAnswered: Bool {
        get {
            return answeredAt > 0
        }
    }
    
    
    init(delegate: CallControlDelegate) {
        self.delegate = delegate
    }
    
    
    func mute(_ mute: Bool) throws {
        WLog.shared.debug("WebitelCall: mute \(mute)")
        try ensureCallOngoing()
        try ensureSipIdValid()
        
        if isMuted == mute {
            WLog.shared.debug("WebitelCall: mute \(mute) - no action needed")
            return
        }
        
        try delegate?.muteCall(withID: sipId, muted: mute)
        isMuted = mute
    }
    
    
    func hold(_ hold: Bool) throws {
        WLog.shared.debug("WebitelCall: hold \(hold)")
        try ensureCallOngoing()
        try ensureSipIdValid()
        
        if isHoldInProgress {
            let message = "Hold/unhold operation already in progress."
            WLog.shared.error(message)
            throw CallError.invalidState(message: message)
        }
        
        if isOnHold == hold {
            WLog.shared.debug("WebitelCall: hold \(hold) - no action needed")
            return
        }
        
        try delegate?.holdCall(withID: sipId, onHold: hold)
        isHoldInProgress = true
    }
    
    
    func sendDTMF(_ digits: String) throws {
        WLog.shared.debug("WebitelCall: sendDTMF \(digits)")
        try ensureCallOngoing()
        try ensureSipIdValid()
        try delegate?.sendDTMF(withID: sipId, digits: digits)
    }
    
    
    func disconnect() throws {
        WLog.shared.debug("WebitelCall: disconnect call")
        if case .disconnected = state {
            WLog.shared.error("Call already disconnected — ignoring")
            throw CallError.invalidState(message: state.description)
        }
        try internalDisconnect(CallEndReason.from(code: 0), cancelTask: true)
    }
    
    
    func disconnectWithReason(callEndReason: CallEndReason) {
        do {
            try internalDisconnect(callEndReason)
        } catch {
            WLog.shared.error("disconnectWithReason: error – \(error)")
        }
    }
    
    
    // MARK: - State & Listeners
    
    func upateState(_ state: CallState) {
        WLog.shared.debug("onCallState: from - \(self.state), to - \(state)")
        self.state = state
        notifyStateChanged(callState: state)
    }
    
    
    func addListener(_ listener: CallListener) {
        listeners.add(listener)
    }
    
    
    func removeListener(_ listener: CallListener) {
        listeners.remove(listener)
    }
    
    
    func removeAllListeners() {
        listeners.removeAllObjects()
    }
    
    
    // MARK: - Async API Task
    
    func apiTask(_ operation: @escaping @Sendable () async throws -> Void) {
        apiConfigTask = Task {
            do {
                upateState(.connecting)
                try await operation()
            } catch {
                WLog.shared.error("apiTask: error – \(error)")
                try? self.disconnect()
            }
        }
    }
    
    
    // MARK: - PJSIP Callbacks
    
    func onHoldCallPJSIP(onHold: Bool) {
        if isOnHold == onHold {
            return
        }
        isOnHold = onHold
        notifyStateChanged(isOnHold: isOnHold)
    }
    
    
    func onConfirmedPJSIP() {
        let date = NSDate()
        answeredAt = Int64(date.timeIntervalSince1970)
        upateState(.ongoing)
    }
    
    
    // MARK: - Private
    
    private func cancelTask() {
        apiConfigTask?.cancel()
        apiConfigTask = nil
    }
    
    
    private func internalDisconnect(_ callEndReason: CallEndReason, cancelTask: Bool = false) throws {
        if case .disconnected = state {
            let message = "already disconnected"
            WLog.shared.warning("unavailable, \(message)")
            throw CallError.invalidState(message: message)
        }
        
        if sipId < 0 {
            if cancelTask {
                self.cancelTask()
            }
            try delegate?.disconnectCall(.local(uuid: id))
            upateState(CallState.disconnected(callEndReason))
            
        } else {
            try delegate?.disconnectCall(.sip(id: sipId))
        }
    }
    
    
    private func safeNotify(_ block: (CallListener) throws -> Void) {
        for case let listener as CallListener in listeners.allObjects {
            do { try block(listener) }
            catch { WLog.shared.error("⚠️ Unhandled exception in client listener: \(error)") }
        }
    }
    
    
    private func notifyStateChanged(callState: CallState) {
        safeNotify { l in
            l.onCallStateChanged(call: self, state: callState)
        }
    }
    
    
    private func notifyStateChanged(isOnHold: Bool) {
        safeNotify { l in
            l.onHoldChanged(call: self, isOnHold: isOnHold)
        }
    }
    
    
    private func ensureCallOngoing() throws {
        guard case .ongoing = state else {
            let message = "Call is not in an ongoing state. Current state: \(state)"
            WLog.shared.error(message)
            throw CallError.invalidState(message: message)
        }
    }
    

    private func ensureSipIdValid() throws {
        guard sipId >= 0 else {
            let message = "SIP id not created yet."
            WLog.shared.error(message)
            throw CallError.invalidState(message: message)
        }
    }
}
