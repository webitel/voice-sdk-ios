//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2025.
//

import Foundation


class AuthManager {
    private let networkConfiguration: NetworkConfiguration
    private var jwt: String = ""
    private var user: User?
    private var api: Api
    
    init(networkConfiguration: NetworkConfiguration) {
        self.networkConfiguration = networkConfiguration
        self.api = Api(networkConfiguration: networkConfiguration)
    }
    
    
    func setUser(_ user: User) {
        self.user = user
    }
    
    
    func setJWT(_ jwt: String) {
        self.jwt = jwt
    }
    
    
    func getSipConfig() async throws -> SipConfig {
        if let user = user {
            return try await fetchSipConfigWithUser(user)
        } else if !jwt.isEmpty {
            return try await fetchSipConfigWithJwt(jwt)
        } else {
            throw CallError.unauthorized(message: "User or JWT not set")
        }
    }
    
    
    private func fetchSipConfigWithUser(_ user: User) async throws -> SipConfig {
        WLog.shared.debug("fetchSipConfigWithUser: sub - \(user.sub); name - \(user.name)")
        
        let request = TokenRequest(
            scope: ["call"],
            grantType: "identity",
            appToken: networkConfiguration.clientToken,
            responseType: ["call", "token"],
            identity: Identity(iss: user.iss, sub: user.sub, name: user.name),
            code: "authorization_code"
        )
        
        let response = try await api.login(request)
        return try processSipResponse(response)
    }
    
    
    private func fetchSipConfigWithJwt(_ value: String) async throws -> SipConfig {
        WLog.shared.debug("fetchSipConfigWithJwt: \(value)")
        
        let response = try await api.getSipConfig(jwt: value)
        return try processSipResponse(response)
    }
    
    
    private func processSipResponse(_ response: AccessTokenResponse) throws -> SipConfig {
        guard let call = response.call else {
            throw CallError.invalidResponse(message: "Sip Config not found in response")
        }
        
        let password = (call.secret?.isEmpty == false ? call.secret : response.accessToken) ?? ""
        
        let config = SipConfig(
            auth: networkConfiguration.deviceId,
            domain: call.realm,
            extension: call.userId,
            password: password,
            proxy: call.proxy
        )
        
        WLog.shared.debug("processSipResponse: \(config)")
        return config
    }
}


