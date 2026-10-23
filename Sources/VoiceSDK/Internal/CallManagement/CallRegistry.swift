//
//  CallRegistry.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// Thread-safe index of live calls by UUID and SIP id, plus the active call.
final class CallRegistry {

    struct State {
        var callsByUUID: [UUID: CallImpl] = [:]
        var callsBySipId: [Int32: UUID] = [:]
        var activeCall: CallImpl?
    }

    enum InsertOutcome {
        case inserted
        case existing
        /// The call was created but not registered; the caller must end it right away.
        case rejected
    }

    private let state = Protected(State())

    var activeCall: CallImpl? {
        state.read { $0.activeCall }
    }

    var calls: [CallImpl] {
        state.read { Array($0.callsByUUID.values) }
    }


    /// Atomically returns the call `existing` picks from the registry, or creates one with
    /// `make` and registers it — so two concurrent `makeCall`s can't both create a call.
    /// If `reject` says the registry can't take another call, the call is created but
    /// not registered.
    func insert(
        existing: (State) -> CallImpl?,
        reject: (State) -> Bool,
        make: () -> CallImpl
    ) -> (call: CallImpl, outcome: InsertOutcome) {
        state.write { registry in
            if let call = existing(registry) {
                return (call, .existing)
            }
            let call = make()
            if reject(registry) {
                return (call, .rejected)
            }
            registry.callsByUUID[call.id] = call
            if registry.activeCall == nil { registry.activeCall = call }
            return (call, .inserted)
        }
    }


    func remove(uuid: UUID) {
        state.write { registry in
            guard let call = registry.callsByUUID.removeValue(forKey: uuid) else { return }
            registry.callsBySipId.removeValue(forKey: call.sipId)
            if registry.activeCall?.id == uuid {
                // The remaining call stays on hold until the app resumes it.
                let remaining = registry.callsByUUID.values
                registry.activeCall = remaining.first { $0.state == .ongoing } ?? remaining.first
            }
        }
    }


    func setActive(_ call: CallImpl) {
        state.write { if $0.activeCall?.id != call.id { $0.activeCall = call } }
    }


    func find(byUUID uuid: UUID) -> CallImpl? {
        state.read { $0.callsByUUID[uuid] }
    }


    func find(bySipId sipId: Int32) -> CallImpl? {
        state.read { registry in
            registry.callsBySipId[sipId].flatMap { registry.callsByUUID[$0] }
        }
    }


    func assignSipId(_ sipId: Int32, to uuid: UUID) {
        state.write { registry in
            guard let call = registry.callsByUUID[uuid] else { return }
            call.sipId = sipId
            registry.callsBySipId[sipId] = uuid
        }
    }


    /// Ongoing calls other than `exceptId` that are neither held nor being held.
    func holdableCalls(except exceptId: UUID) -> [CallImpl] {
        state.read { registry in
            registry.callsByUUID.values.filter {
                $0.id != exceptId && $0.state == .ongoing && !$0.isOnHold && !$0.isHoldInProgress
            }
        }
    }


    func hasOtherOngoingCall(except exceptId: UUID) -> Bool {
        state.read { $0.callsByUUID.values.contains { $0.id != exceptId && $0.state == .ongoing } }
    }
}
