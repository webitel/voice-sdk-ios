//
//  PushSubscriptionRequest.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation

struct PushSubscriptionRequest: Encodable {
    let pnType: String
    let pnRpid: String

    enum CodingKeys: String, CodingKey {
        case pnType = "pn-type"
        case pnRpid = "pn-rpid"
    }
}
