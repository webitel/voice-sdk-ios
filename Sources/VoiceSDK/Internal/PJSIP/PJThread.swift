//
//  PJThread.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation
import PJSIPKit


/// Registers the current thread with pjlib if needed.
///
/// GCD may run blocks of the serial `SDKQueues.sip` queue on different threads, so
/// every pjsua entry point calls this. pjlib requires the thread descriptor to stay
/// valid for the whole lifetime of the thread, so it is heap-allocated and
/// intentionally never freed (one small buffer per GCD worker thread).
func registerPJThread() {
    // Before pjsua_create / after pjsua_destroy pjlib is not initialized.
    guard pjsua_get_state() != PJSUA_STATE_NULL, pj_thread_is_registered() == 0 else { return }

    let size = Int(PJ_THREAD_DESC_SIZE)
    let desc = UnsafeMutablePointer<Int>.allocate(capacity: size)
    desc.initialize(repeating: 0, count: size)

    var thread: OpaquePointer?
    pj_thread_register(nil, desc, &thread)
}


/// `registerPJThread` for code that must run on `SDKQueues.sip`.
func registerSipThread() {
    SDKQueues.assertOnSip()
    registerPJThread()
}


/// pjsua is fully started and its API can be used.
var isPjsuaRunning: Bool {
    pjsua_get_state() == PJSUA_STATE_RUNNING
}


/// Work can be enqueued on `SDKQueues.sip` before a `destroy` and run after it —
/// pjsua must not be touched then.
func ensurePjsuaRunning() throws {
    registerSipThread()
    guard isPjsuaRunning else {
        throw CallError.invalidState(message: "SIP stack is not running")
    }
}
