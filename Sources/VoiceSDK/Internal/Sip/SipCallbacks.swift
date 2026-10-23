//
//  SipCallbacks.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 01.07.2025.
//

import Foundation
import PJSIPKit

private let sipCallbacksLogger = SDKLogger.make("voice.core.sip")

// These run on PJSIP worker threads, possibly while pjsua locks are held: copy
// whatever is needed out of the PJSIP structures here, then hop to `SDKQueues.sip`
// with `async` (never `sync`) — see `SDKQueues`.


func on_call_media_state(call_id: pjsua_call_id) {
    SDKQueues.sip.async {
        VoiceManager.shared.onCallMediaState(sipId: call_id)
    }
}

func on_call_media_event(call_id: pjsua_call_id, med_idx: UInt32, e: UnsafeMutablePointer<pjmedia_event>?) {
    guard let e, e.pointee.type == PJMEDIA_EVENT_FMT_CHANGED else { return }

    // Only plain values cross to `SDKQueues.sip`: the media info (and its render window
    // id) is re-read there, since the window may be gone by the time the hop runs.
    let fmtChanged = e.pointee.data.fmt_changed
    guard fmtChanged.dir == PJMEDIA_DIR_DECODING else { return }

    let newWidth = fmtChanged.new_fmt.det.vid.size.w
    let newHeight = fmtChanged.new_fmt.det.vid.size.h
    let newFpsNum = fmtChanged.new_fmt.det.vid.fps.num
    let newFpsDenum = fmtChanged.new_fmt.det.vid.fps.denum

    sipCallbacksLogger.debug("onCallMediaEvent: remote video format changed to \(newWidth)x\(newHeight) @ \(newFpsNum)/\(newFpsDenum)fps")
    SDKQueues.sip.async {
        VoiceManager.shared.onRemoteVideoFormatChanged(
            sipId: call_id,
            mediaIndex: Int(med_idx),
            newWidth: newWidth,
            newHeight: newHeight
        )
    }
}


func on_call_tsx_state(
    call_id: pjsua_call_id,
    tsx: UnsafeMutablePointer<pjsip_transaction>?,
    e: UnsafeMutablePointer<pjsip_event>?
) {
    guard let tsx = tsx, let e = e else { return }
    guard e.pointee.body.tsx_state.type == PJSIP_EVENT_RX_MSG else { return }
    guard pjStrToString(tsx.pointee.method.name) == "INFO" else { return }
    guard let rdata = e.pointee.body.tsx_state.src.rdata else { return }
    let len = Int(rdata.pointee.pkt_info.len)
    let wholeMsg = withUnsafeBytes(of: rdata.pointee.pkt_info.packet) { raw -> String in
        String(decoding: raw.bindMemory(to: UInt8.self).prefix(len), as: UTF8.self)
    }
    SDKQueues.sip.async {
        VoiceManager.shared.onIncomingInfo(sipId: call_id, wholeMsg: wholeMsg)
    }

    // The on_call_tsx_state event also fires for the 200 OK response to our own outgoing
    // INFO (a UAC transaction) — only answer when we're the UAS (server) side, i.e. this is
    // a genuine incoming INFO request, to avoid PJSIP retransmitting it as unanswered.
    // pjsua answers DTMF/media-control INFOs itself, and a second final response on the
    // same transaction is invalid — so skip those and anything already answered.
    guard tsx.pointee.role == PJSIP_ROLE_UAS,
          tsx.pointee.state == PJSIP_TSX_STATE_TRYING,
          tsx.pointee.status_code < 200,
          !isAnsweredByPjsua(rdata) else { return }
    var tdata: UnsafeMutablePointer<pjsip_tx_data>?
    guard pjsip_endpt_create_response(pjsua_get_pjsip_endpt(), rdata, 200, nil, &tdata) == PJ_SUCCESS.rawValue,
          let tdata else {
        return
    }
    // On failure the transaction doesn't take over the reference.
    if pjsip_tsx_send_msg(tsx, tdata) != PJ_SUCCESS.rawValue {
        pjsip_tx_data_dec_ref(tdata)
    }
}


/// INFO bodies pjsua responds to on its own (see `pjsua_call_on_tsx_state_changed`).
private func isAnsweredByPjsua(_ rdata: UnsafeMutablePointer<pjsip_rx_data>) -> Bool {
    guard let body = rdata.pointee.msg_info.msg?.pointee.body, body.pointee.len > 0 else { return false }
    let type = pjStrToString(body.pointee.content_type.type)?.lowercased()
    let subtype = pjStrToString(body.pointee.content_type.subtype)?.lowercased()
    return type == "application" && (subtype == "dtmf-relay" || subtype == "media_control+xml")
}


func on_call_state(call_id: pjsua_call_id, e: UnsafeMutablePointer<pjsip_event>?) -> Void {
    // A zeroed `ci` would report state NULL for call id 0 — someone else's call.
    var ci = pjsua_call_info()
    guard pjsua_call_get_info(call_id, &ci) == PJ_SUCCESS.rawValue else {
        sipCallbacksLogger.warning("on_call_state: failed to get call info for \(call_id)")
        return
    }

    let state = ci.state
    let sipId = call_id
    let lastStatusCode = Int(ci.last_status.rawValue)
    let lastReason = pjStrToString(ci.last_status_text)
    SDKQueues.sip.async {
        VoiceManager.shared.onCallState(
            state: state,
            sipId: sipId,
            lastStatusCode: lastStatusCode,
            lastReason: lastReason
        )
    }
}


func on_incoming_call(acc_id: pjsua_acc_id, call_id: pjsua_call_id, rdata: UnsafeMutablePointer<pjsip_rx_data>?) {
    // The server tags the INVITE with the `call_id` from the push, which is the
    // `Call.id` of the incoming call created in `handleIncomingPush`.
    var callUuid: UUID?
    if let msg = rdata?.pointee.msg_info.msg {
        let rawName = strdup("X-Webitel-Uuid")
        defer { free(rawName) }
        var name = pj_str(rawName)
        if let hdr = pjsip_msg_find_hdr_by_name(msg, &name, nil) {
            let value = pjStrToString(hdr.load(as: pjsip_generic_string_hdr.self).hvalue)
            callUuid = value.flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    sipCallbacksLogger.debug("on_incoming_call: sipId=\(call_id), X-Webitel-Uuid=\(callUuid?.uuidString ?? "nil")")
    SDKQueues.sip.async { [callUuid] in
        VoiceManager.shared.onIncomingCall(sipId: call_id, callUuid: callUuid)
    }
}


func on_reg_state2(acc_id: pjsua_acc_id, info: UnsafeMutablePointer<pjsua_reg_info>?) {
    guard let param = info?.pointee.cbparam?.pointee else { return }
    // expiration == 0 is the un-REGISTER sent on shutdown — nothing waits for it.
    guard param.expiration > 0 || param.code >= 300 || param.status != PJ_SUCCESS.rawValue else { return }

    let code: Int
    if param.status == PJ_SUCCESS.rawValue {
        code = Int(param.code)
    } else {
        // Auth failures arrive as status=PJSIP_EAUTH* with the registrar's real code (e.g. 401);
        // fall back to 408 only when no final response was received (transport error / timeout).
        code = param.code >= 300 ? Int(param.code) : 408
        sipCallbacksLogger.error("on_reg_state2: code=\(param.code), status=\(param.status) (\(pjStatusToString(param.status)))")
    }
    let reason = pjStrToString(param.reason)
    SDKQueues.sip.async {
        VoiceManager.shared.onRegistrationState(code: code, reason: reason)
    }
}
