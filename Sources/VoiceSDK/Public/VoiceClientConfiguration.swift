//
//  VoiceClientConfiguration.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 09.07.2026.
//

import Foundation
import Logging


public struct VoiceClientConfiguration {

    public var clientToken: String?

    /// Logging level for SDK internal logs.
    ///
    /// Default: `.error`
    public var logLevel: Logger.Level = .error
    
    
    /// Custom log handler factory used to intercept and process internal SDK logs.
    public var logHandler: ((String) -> LogHandler)?


    /// Collection of Base64-encoded SHA-256 public key hashes (SPKI)
    /// used for SSL pinning.
    ///
    /// If empty, SSL pinning is disabled.
    public var pinnedPublicKeys: [String] = []


    /// Unique device identifier used for session tracking.
    ///
    /// If not provided, SDK may generate one automatically.
    public var deviceId: String?


    /// Maximum time, in seconds, from handling an incoming call push until the
    /// SIP INVITE arrives. If exceeded, the incoming call ends with `.requestTimeout`.
    ///
    /// Default: `15`
    public var incomingCallTimeout: TimeInterval = 15
}
