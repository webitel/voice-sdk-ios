//
//  AuthManager.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2025.
//

import Foundation


actor AuthManager {
    private let logger = SDKLogger.make("voice.auth")
    private let context: ClientContext
    private let api: TokenAPI
    /// Last access token obtained while fetching the SIP config: the provider JWT
    /// for `.token`, or the token returned by login for `.contact`.
    private var accessToken: String?

    init(context: ClientContext, api: TokenAPI) {
        self.context = context
        self.api = api
    }
    
    
    func getSipConfig(meetingId: String?) async throws -> SipConfig {
        let meetingId = (meetingId?.isEmpty == false) ? meetingId : nil
        switch context.authMethod {
        case .contact(let identity):
                logger.debug("Using contact identity for login")
            return try await fetchSipConfigWithUser(identity, meetingId: meetingId)
        case .token(let provider):
                logger.debug("Using token from provider")
                let token = provider()
            return try await fetchSipConfigWithJwt(token)
        }
    }


    private func fetchSipConfigWithUser(_ contact: ContactIdentity, meetingId: String?) async throws -> SipConfig {
        logger.debug("fetchSipConfigWithUser: sub - \(contact.sub); name - \(contact.name)")

        let request = TokenRequest(
            scope: ["call"],
            grantType: "identity",
            appToken: context.clientToken,
            responseType: ["call", "token"],
            identity: Identity(iss: contact.iss, sub: contact.sub, name: contact.name),
            code: "authorization_code",
            meetingId: meetingId
        )

        let response = try await api.login(request)
        return try processSipResponse(response)
    }
    
    
    private func fetchSipConfigWithJwt(_ value: String) async throws -> SipConfig {
        let response = try await api.getSipConfig(jwt: value)
        accessToken = value
        return try processSipResponse(response)
    }


    // MARK: - Access token

    /// Token for authenticated non-SIP requests (push subscription/confirmation).
    func currentAccessToken() async throws -> String {
        if case .token(let provider) = context.authMethod {
            accessToken = provider()
        } else if accessToken == nil {
            _ = try await getSipConfig(meetingId: nil)
        }
        guard let accessToken, !accessToken.isEmpty else {
            throw CallError.unauthorized(message: "Access token is not available")
        }
        return accessToken
    }
    
    
    private func processSipResponse(_ response: AccessTokenResponse) throws -> SipConfig {
        guard let call = response.call else {
            throw CallError.invalidResponse(message: "Sip Config not found in response")
        }

        if let token = response.accessToken, !token.isEmpty {
            accessToken = token
        }
        let password = (call.secret?.isEmpty == false ? call.secret : response.accessToken) ?? ""

        let config = SipConfig(
            auth: context.deviceId,
            domain: call.realm,
            extension: call.userId,
            password: password,
            proxy: call.proxy
        )

        logger.debug("processSipResponse: extension=\(config.getExtension()), domain=\(config.getDomain()), proxy=\(config.getProxy())")
        return config
    }
}
