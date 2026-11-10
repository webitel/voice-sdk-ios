//
//  ClientContext.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 09.07.2026.
//

import Foundation

internal struct ClientContext {
    public let baseURL: URL
    public let clientToken: String
    public let authMethod: AuthMethod
    public let callSettings: CallSettings
    public let deviceId: String
    public let agent: String
    public var pinnedHashes: [String]
    public let incomingCallTimeout: TimeInterval
    /// Effective mode: `.sdkManaged` falls back to `.none` if CallKit is already managed by another client.
    public let systemCallIntegration: SystemCallIntegration

    public init(
        baseURL: URL,
        clientToken: String,
        authMethod: AuthMethod,
        callSettings: CallSettings,
        deviceId: String,
        agent: String,
        pinnedHashes: [String] = [],
        incomingCallTimeout: TimeInterval = 15,
        systemCallIntegration: SystemCallIntegration = .none
    ) {
        self.baseURL = baseURL
        self.clientToken = clientToken
        self.authMethod = authMethod
        self.callSettings = callSettings
        self.deviceId = deviceId
        self.agent = agent
        self.pinnedHashes = pinnedHashes
        self.incomingCallTimeout = incomingCallTimeout
        self.systemCallIntegration = systemCallIntegration
    }
}
