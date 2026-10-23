//
//  PushAPI.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// VoIP push subscription and incoming-call push confirmation.
struct PushAPI {
    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }


    /// Tells the server that the SIP account is registered and the incoming call
    /// announced by a push can now be delivered. The response body is empty.
    func confirmPush(callId: UUID, accessToken: String) async throws {
        let path = "/api/calls/active/\(callId.uuidString.lowercased())/confirm_push"
        var request = try http.makeRequest(path: path, method: "PATCH")
        request.addValue(accessToken, forHTTPHeaderField: "X-Webitel-Access")

        try await http.sendNoContent(request, label: "confirmPush")
    }


    /// Subscribes this device to VoIP pushes. `pushToken` is the hex-encoded
    /// PushKit token.
    func subscribePush(pushToken: String, accessToken: String) async throws {
        var request = try http.makeRequest(path: "/api/push/subscription", method: "PUT")
        request.addValue(accessToken, forHTTPHeaderField: "X-Webitel-Access")
        request.httpBody = http.encodeBody(PushSubscriptionRequest(pnType: "apns", pnRpid: pushToken))

        try await http.sendNoContent(request, label: "subscribePush")
    }
}
