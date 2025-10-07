//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//

import Foundation


struct TokenRequest: Codable {
    let scope: [String]
    let grantType: String
    let appToken: String
    let responseType: [String]
    let identity: Identity
    let code: String

    enum CodingKeys: String, CodingKey {
        case scope
        case grantType = "grant_type"
        case appToken = "app_token"
        case responseType = "response_type"
        case identity
        case code
    }
}


struct Identity: Codable {
    let iss: String
    let sub: String
    let name: String
}
