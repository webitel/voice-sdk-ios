//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// Represents a user with details such as name, email, phone number, and localization information.
public struct User {
    
    /// Issuer Identifier.
    /// A case-sensitive URL that identifies the provider of the response.
    public let iss: String
    
    /// Subject Identifier.
    /// A unique identifier for the End-User within the Issuer.
    public let sub: String
    
    /// The full name of the End-User, displayed according to their preferences.
    public let name: String
    
    /// The email address of the End-User. This field is optional.
    public let email: String?
    
    /// Indicates whether the End-User's email has been verified.
    public let emailVerified: Bool
    
    /// The phone number of the End-User. This field is optional.
    public let phoneNumber: String?
    
    /// Indicates whether the End-User's phone number has been verified.
    public let phoneNumberVerified: Bool
    
    /// The locale of the End-User, typically represented as a BCP47 language tag (e.g., "en-US"). This field is optional.
    public let locale: String?
    
    /// Initializes a `User` object with required and optional fields.
    /// - Parameters:
    ///   - iss: Issuer Identifier (URL of the provider).
    ///   - sub: Subject Identifier (unique user ID).
    ///   - name: Full name of the user.
    ///   - email: Optional email of the user.
    ///   - emailVerified: Boolean flag indicating if the email is verified (default: `false`).
    ///   - phoneNumber: Optional phone number of the user.
    ///   - phoneNumberVerified: Boolean flag indicating if the phone number is verified (default: `false`).
    ///   - locale: Optional locale in BCP47 format (e.g., "en-US").
    public init(
        iss: String,
        sub: String,
        name: String,
        email: String? = nil,
        emailVerified: Bool = false,
        phoneNumber: String? = nil,
        phoneNumberVerified: Bool = false,
        locale: String? = nil
    ) {
        self.iss = iss
        self.sub = sub
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.phoneNumber = phoneNumber
        self.phoneNumberVerified = phoneNumberVerified
        self.locale = locale
    }
}
