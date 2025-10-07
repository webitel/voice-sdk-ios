//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// A builder class used to configure and create a `VoiceClient`.
///
/// This builder follows the fluent interface pattern, allowing you
/// to chain configuration methods before calling `build()`.
public final class VoiceClientBuilder {
    /// The server address.
    var address: String
    
    /// The authentication token (e.g., JWT) used for connecting.
    var token: String

    /// An optional user associated with this client.
    var user: User?
    
    /// Defines the verbosity of logging. Defaults to `.error`.
    var logLevel: LogLevel = .error
    
    /// A unique identifier of the device. Defaults to an empty string.
    var deviceId: String = ""
    
    /// The version of the application. Defaults to `"0.0.0"`.
    var version: String = "0.0.0"
    
    /// The application display name.
    var name: String = ""

    /// Optional call-specific configuration such as audio and network options.
    var settings: CallSettings?
    
    
    /// Initializes the builder with mandatory connection parameters.
    ///
    /// - Parameters:
    ///   - address: The signaling or backend server address.
    ///   - token: The authentication token (e.g., JWT).
    public init(address: String, token: String) {
        self.address = address
        self.token = token
    }
    
    
    /// Sets the user for the voice client.
    ///
    /// If the user is already known at the time of building,
    /// it can be passed here instead of calling `setUser` later.
    ///
    /// - Parameter user: The `User` instance representing the logged-in user.
    /// - Returns: The same builder instance for chaining.
    public func user(_ user: User) -> Self {
        self.user = user
        return self
    }

    
    /// Sets the logging level for the client.
    ///
    /// - Parameter level: A `LogLevel` value such as `.error`, `.info`, or `.debug`.
    /// - Returns: The same builder instance for chaining.
    public func logLevel(_ level: LogLevel) -> Self {
        self.logLevel = level
        return self
    }
    
    
    /// Configures the client with general call-related settings.
    ///
    /// - Parameter settings: A `CallSettings` object that controls
    ///   audio, networking, and other call options.
    /// - Returns: The same builder instance for chaining.
    public func configure(_ settings: CallSettings) -> Self {
        self.settings = settings
        return self
    }

    
    /// Sets the application display name.
    ///
    /// - Parameter name: The name of the application.
    /// - Returns: The same builder instance for chaining.
    public func appName(_ name: String) -> Self {
        self.name = name
        return self
    }
    
    
    /// Sets the application version string.
    ///
    /// - Parameter version: The version number of the app.
    /// - Returns: The same builder instance for chaining.
    public func appVersion(_ version: String) -> Self {
        self.version = version
        return self
    }
    
    
    /// Sets the device identifier used for uniquely identifying the client.
    ///
    /// - Parameter id: A unique device ID.
    /// - Returns: The same builder instance for chaining.
    public func deviceId(_ id: String) -> Self {
        self.deviceId = id
        return self
    }
    
    
    /// Finalizes the configuration and creates a `VoiceClient` instance.
    ///
    /// - Returns: A fully constructed `VoiceClient` with the provided settings.
    public func build() -> VoiceClient {
        return WebitelVoiceClient(builder: self)
    }
}
