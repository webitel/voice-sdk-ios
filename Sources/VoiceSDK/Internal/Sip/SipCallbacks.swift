//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 01.07.2025.
//

import Foundation
import PJSIPKit


func on_call_media_state(call_id: pjsua_call_id) {
    VoiceManager.shared.onCallMediaState(sipId: call_id)
}


func on_call_state(call_id: pjsua_call_id, e: UnsafeMutablePointer<pjsip_event>?) -> Void {
    var ci = pjsua_call_info()
    pjsua_call_get_info(call_id, &ci)
    
    VoiceManager.shared.onCallState(
        state: ci.state,
        sipId: ci.id,
        lastStatusCode: Int(ci.last_status.rawValue),
        lastReason: pjStrToString(ci.last_status_text)
    )
}


private func pjStrToString(_ str: pj_str_t?) -> String? {
    guard let s = str, s.slen > 0, let basePtr = s.ptr else { return nil }
    let count = Int(s.slen)
    let buffer = UnsafeBufferPointer(start: basePtr, count: count)
    let uint8Buffer = buffer.map { UInt8(bitPattern: $0) }
    return String(decoding: uint8Buffer, as: UTF8.self)
}
