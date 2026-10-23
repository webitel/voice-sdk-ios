//
//  PushService.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// VoIP push flows that need the current access token from `AuthManager`.
struct PushService {
    private let authManager: AuthManager
    private let api: PushAPI

    init(authManager: AuthManager, api: PushAPI) {
        self.authManager = authManager
        self.api = api
    }


    func confirmPush(callId: UUID) async throws {
        let token = try await authManager.currentAccessToken()
        try await api.confirmPush(callId: callId, accessToken: token)
    }


    func registerPushToken(_ pushToken: Data) async throws {
        let hex = pushToken.map { String(format: "%02X", $0) }.joined()
        let token = try await authManager.currentAccessToken()
        try await api.subscribePush(pushToken: hex, accessToken: token)
    }
}
