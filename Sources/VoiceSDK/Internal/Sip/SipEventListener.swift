//
//  SipEventListener.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 02.07.2025.
//

import Foundation
import PJSIPKit


protocol SipEventListener: AnyObject {
    func onCallState(state: pjsip_inv_state, sipId: Int32, lastStatusCode: Int, lastReason: String?)
    func onCallMediaState(sipId: Int32)

    /// A SIP INFO packet was received for the given call, carrying the raw message
    /// (headers + body) exactly as received off the wire — see `MediaStateInfo`.
    func onIncomingInfo(sipId: Int32, wholeMsg: String)

    /// A SIP INVITE was received. `callUuid` is the value of its `X-Webitel-Uuid` header.
    func onIncomingCall(sipId: Int32, callUuid: UUID?)

    /// The registrar answered a REGISTER with the given final status code.
    func onRegistrationState(code: Int, reason: String?)
}
