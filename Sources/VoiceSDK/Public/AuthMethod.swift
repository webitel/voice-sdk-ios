//
//  AuthMethod.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 09.07.2026.
//

import Foundation

/// Authentication method used by the voice client.
public enum AuthMethod {

    /// Authentication using an access token.
    /// The token is provided via closure to allow dynamic refresh.
    case token(
        tokenProvider: () -> String
    )

    /// Authentication using a contact identity.
    case contact(
        identity: ContactIdentity
    )
}


extension AuthMethod: CustomStringConvertible {

    public var description: String {

        switch self {
        case .token:
            return "AuthMethod.Token"

        case .contact:
            return "AuthMethod.Contact"
        }
    }
}
