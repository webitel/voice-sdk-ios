//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 02.07.2025.
//

import Foundation
import PJSIPKit


protocol SipEventListener: AnyObject {
    func onCallState(state: pjsip_inv_state, sipId: Int32, lastStatusCode: Int, lastReason: String?)
    func onCallMediaState(sipId: Int32)
}
