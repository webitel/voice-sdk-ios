//
//  ContactIdentity.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// Represents contact identity information used for session creation.
///
/// This model is provided by the SDK client and sent to backend
/// to create or restore a chat session.
///
/// The structure is compatible with common OpenID Connect identity claims.
public struct ContactIdentity: Encodable {

    /// Unique subject identifier (stable contact ID).
    ///
    /// This is the primary identity field.
    /// Example: external CRM ID, UUID, or internal user ID.
    public let sub: String

    /// Issuer identifier
    public let iss: String

    /// Full display name
    public let name: String

    /// First name
    public let givenName: String?

    /// Middle name
    public let middleName: String?

    /// Last name
    public let familyName: String?

    /// Email address
    public let email: String?

    /// Whether email was verified
    public let emailVerified: Bool?

    /// Phone number in E.164 format
    public let phoneNumber: String?

    /// Whether phone number was verified
    public let phoneNumberVerified: Bool?

    /// Birthdate (ISO 8601: YYYY-MM-DD)
    public let birthdate: String?

    /// Gender (free text, e.g. "male", "female", "other")
    public let gender: String?

    /// Locale (e.g. "en-US", "uk-UA")
    public let locale: String?

    /// Timezone (e.g. "Europe/Kyiv")
    public let zoneinfo: String?

    /// Additional custom metadata associated with this identity.
    public let metadata: [String: String?]?


    public init(
        sub: String,
        iss: String,
        name: String,
        givenName: String? = nil,
        middleName: String? = nil,
        familyName: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        phoneNumber: String? = nil,
        phoneNumberVerified: Bool? = nil,
        birthdate: String? = nil,
        gender: String? = nil,
        locale: String? = nil,
        zoneinfo: String? = nil,
        metadata: [String: String?]? = nil
    ) {

        self.sub = sub
        self.iss = iss
        self.name = name
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.email = email
        self.emailVerified = emailVerified
        self.phoneNumber = phoneNumber
        self.phoneNumberVerified = phoneNumberVerified
        self.birthdate = birthdate
        self.gender = gender
        self.locale = locale
        self.zoneinfo = zoneinfo
        self.metadata = metadata
    }
}
