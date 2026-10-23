//
//  SDKQueues.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// Threading model of the SDK:
/// - `sip` — the only queue that touches pjsua and the mutable state of
///   `VoiceManager`, `SipManager` and `CallImpl`. Public API methods validate
///   synchronously and enqueue the actual work here, so they never block the caller.
///   PJSIP callbacks (worker threads) only copy their data and hop here with `async`
///   — never `sync`, or a pjsua lock held by the worker thread could deadlock.
/// - `events` — delivers `CallObserver.onEvent` in order, separately from `sip`,
///   so a slow observer can't stall SIP processing.
enum SDKQueues {
    static let sip = DispatchQueue(label: "com.webitel.voice.sip", qos: .userInitiated)
    static let events = DispatchQueue(label: "com.webitel.voice.events", qos: .userInitiated)


    static func assertOnSip() {
    #if DEBUG
        dispatchPrecondition(condition: .onQueue(sip))
    #endif
    }


    /// Runs `body` on the `sip` queue and returns its result to the async caller.
    static func onSip<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            sip.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }
}
