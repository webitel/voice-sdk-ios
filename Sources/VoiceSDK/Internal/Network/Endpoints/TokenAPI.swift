//
//  TokenAPI.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2026.
//

import Foundation


/// `/api/portal/token` — exchanges credentials for an access token and SIP config.
struct TokenAPI {
    private let path = "/api/portal/token"
    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }


    func getSipConfig(jwt: String) async throws -> AccessTokenResponse {
        var request = try http.makeRequest(path: path, method: "GET")
        request.addValue(jwt, forHTTPHeaderField: "X-Webitel-Access")

        return try await http.send(request, label: "getSipConfig")
    }


    func login(_ body: TokenRequest) async throws -> AccessTokenResponse {
        var request = try http.makeRequest(path: path, method: "POST")
        request.httpBody = http.encodeBody(body)

        return try await http.send(request, label: "login")
    }
}
