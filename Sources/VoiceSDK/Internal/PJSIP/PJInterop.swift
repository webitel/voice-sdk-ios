//
//  PJInterop.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation
import PJSIPKit


/// C strings handed to PJSIP calls that copy what they keep — freed by the caller
/// once the call returns.
struct OwnedCStrings {
    private var pointers: [UnsafeMutablePointer<CChar>] = []

    mutating func pjString(_ string: String) -> pj_str_t {
        guard let cString = strdup(string) else { return pj_str_t() }
        pointers.append(cString)
        return pj_str(cString)
    }

    mutating func free() {
        pointers.forEach { Foundation.free($0) }
        pointers.removeAll()
    }
}


func pjStatusToString(_ status: pj_status_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(PJ_ERR_MSG_SIZE))
    _ = pj_strerror(status, &buffer, pj_size_t(buffer.count))
    return String(cString: buffer)
}


func pjStrToString(_ str: pj_str_t?) -> String? {
    guard let s = str, s.slen > 0, let basePtr = s.ptr else { return nil }
    let count = Int(s.slen)
    let buffer = UnsafeBufferPointer(start: basePtr, count: count)
    let uint8Buffer = buffer.map { UInt8(bitPattern: $0) }
    return String(decoding: uint8Buffer, as: UTF8.self)
}


/// Converts a fixed-size C array imported as a tuple (e.g. `pjsua_call_info.media`) to an array.
func tupleToArray<Tuple, Value>(_ tuple: Tuple) -> [Value] {
    Mirror(reflecting: tuple).children.compactMap { $0.value as? Value }
}


func getMediaInfo(_ ci: pjsua_call_info, index: Int) -> pjsua_call_media_info? {
    switch index {
    case 0: return ci.media.0
    case 1: return ci.media.1
    case 2: return ci.media.2
    case 3: return ci.media.3
    case 4: return ci.media.4
    case 5: return ci.media.5
    case 6: return ci.media.6
    case 7: return ci.media.7
    case 8: return ci.media.8
    case 9: return ci.media.9
    case 10: return ci.media.10
    case 11: return ci.media.11
    case 12: return ci.media.12
    case 13: return ci.media.13
    case 14: return ci.media.14
    case 15: return ci.media.15
    default: return nil
    }
}
